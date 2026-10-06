#!/usr/bin/env python3
"""Offline lifecycle regressions: real wrapper/jobs, a local agy process fixture."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
DELEGATE = ROOT / "scripts/agy-delegate.sh"
JOB = ROOT / "scripts/agy-job.sh"
STUB = r'''#!/usr/bin/env python3
import json, os, signal, subprocess, sys, time
from pathlib import Path
root = Path(os.environ["FIXTURE_DIR"])
case = os.environ.get("LIFECYCLE_CASE", "success")
if "--help" in sys.argv:
    if case == "probe_hang":
        (root / "probe-ready").touch()
        while True: time.sleep(1)
    print("--output-format json")
    sys.exit(0)
with (root / "invocations").open("a") as f: f.write("main\n")
if case == "success":
    if "--output-format" in sys.argv:
        print(json.dumps({"status": "SUCCESS", "response": "digest: ok",
            "conversation_id": "test-conversation", "usage": {"input_tokens": 2}}))
    else: print("digest: ok")
    sys.exit(0)
(root / "completed-edit.txt").write_text("useful edit already on disk\n")
print("partial reply", flush=True)
print("executor diagnostic", file=sys.stderr, flush=True)
if case == "partial_timeout":
    print("[agy] print timeout after 1s with turn in progress; returning partial output", file=sys.stderr)
    sys.exit(0)
child = subprocess.Popen([sys.executable, "-c", ''' + repr(r'''
import os, signal, sys, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
with open(sys.argv[1], "a") as f:
    while True:
        f.write("working\n"); f.flush(); time.sleep(0.02)
''') + r''', str(root / "heartbeat")])
(root / "descendant_pid").write_text(str(child.pid))
while True: time.sleep(1)
'''


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agy-lifecycle-")
        self.root = Path(self.tmp.name).resolve()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.agy = self.bin / "agy"
        self.agy.write_text(STUB)
        self.agy.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        AGY_CONFIG=str(self.root / "no-config"),
                        AGY_RUNS_DIR=str(self.root / 'runs with "quotes"'),
                        ANTIGRAVITY_JOBS=str(self.root / "jobs"),
                        FIXTURE_DIR=str(self.root), AGY_STRUCTURED_OUTPUT="off")
        # Do not read or write the developer's accounting/config defaults.
        for key in ("AGY_USAGE_LOG", "AGY_TIMEOUT", "AGY_DEFAULT_MODEL", "AGY_DELEGATE"):
            self.env.pop(key, None)
        self.processes = []
        self.streams = []
        self.cleaned_groups = set()

    def cleanup_orphaned_groups(self):
        # Completed wrappers already clean their children. After SIGKILL, the
        # record survives but can quickly become stale: signal each orphaned
        # group at most once, including when cleanup runs again in tearDown.
        for record in Path(self.env["AGY_RUNS_DIR"]).glob("*/child_pid"):
            if (record.parent / "exit_code").exists():
                continue
            try:
                group = int(record.read_text())
            except ValueError:
                continue
            if group in self.cleaned_groups:
                continue
            try:
                os.killpg(group, signal.SIGKILL)
            except ProcessLookupError:
                pass
            # A real permission failure must still fail the test. Only mark a
            # group cleaned after the signal succeeded or it no longer exists.
            self.cleaned_groups.add(group)

    def tearDown(self):
        try:
            for p in self.processes:
                if p.poll() is None:
                    p.terminate()
                    try:
                        p.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        p.kill()
                        p.wait(timeout=2)
        finally:
            try:
                self.cleanup_orphaned_groups()
            finally:
                for stream in self.streams:
                    stream.close()
                self.tmp.cleanup()

    def call(self, *args, env=None, timeout=20):
        return subprocess.run([str(DELEGATE), *args], cwd=self.root,
                              env=env or self.env, capture_output=True, text=True, timeout=timeout)

    def launch(self, case="hang", extra=(), env=None):
        launch_env = dict(env or self.env, LIFECYCLE_CASE=case)
        out = (self.root / "tool.out").open("w")
        err = (self.root / "tool.err").open("w")
        self.streams += [out, err]
        p = subprocess.Popen([str(DELEGATE), "--timeout", "15m", *extra, "task"],
                             cwd=self.root, env=launch_env, stdout=out, stderr=err,
                             start_new_session=True)
        self.processes.append(p)
        return p

    def eventually(self, predicate, seconds=5):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if predicate():
                return
            time.sleep(0.02)
        self.fail("condition did not become true before deadline")

    def run_dir(self):
        records = list(Path(self.env["AGY_RUNS_DIR"]).glob("*/run.json"))
        self.assertEqual(len(records), 1)
        return records[0].parent

    def worker_ready(self):
        self.eventually(lambda: (self.root / "heartbeat").exists()
                        and (self.root / "heartbeat").stat().st_size > 0)

    def assert_writer_stopped(self):
        heartbeat = self.root / "heartbeat"
        size = heartbeat.stat().st_size
        time.sleep(0.15)
        self.assertEqual(size, heartbeat.stat().st_size, "descendant is still writing")

    def test_budget_is_read_only_and_covers_all_deadlines(self):
        result = self.call("--timeout", "15m", "--print-budget")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {
            "print_timeout_seconds": 900, "guard_timeout_seconds": 1020,
            "minimum_harness_timeout_seconds": 1080})
        self.assertFalse((self.root / "invocations").exists())
        self.assertFalse(Path(self.env["AGY_RUNS_DIR"]).exists())
        for duration, expected in [("1s", 71), ("005m", 435), ("1h", 3780)]:
            result = self.call("--timeout", duration, "--print-budget")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["minimum_harness_timeout_seconds"], expected)
        for duration in ("0", "-1", "bad", "1.5m", "999999999999999999h"):
            result = self.call("--timeout", duration, "--print-budget")
            self.assertNotEqual(result.returncode, 0, duration)

    def test_success_retains_raw_envelope_and_conversation_without_changing_stdout(self):
        result = self.call("task", env=dict(self.env, AGY_STRUCTURED_OUTPUT="on"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "digest: ok\n")
        start = next(line[8:] for line in result.stderr.splitlines() if line.startswith("AGY_RUN "))
        meta = json.loads(start)
        rd = self.run_dir()
        self.assertEqual(meta["log_dir"], str(rd))
        self.assertEqual(rd.stat().st_mode & 0o777, 0o700)
        self.assertEqual((rd / "stdout").stat().st_mode & 0o777, 0o600)
        self.assertEqual((rd / "state").read_text().strip(), "done")
        self.assertEqual((rd / "exit_code").read_text().strip(), "0")
        self.assertEqual(json.loads((rd / "stdout").read_text())["conversation_id"], "test-conversation")
        self.assertIn("test-conversation", (rd / "events.log").read_text())
        self.assertEqual((rd / "response").read_text(), "digest: ok")
        # Completion records make these PID files stale, even if the OS has
        # already recycled the group ID. Cleanup must not signal them again.
        with mock.patch.object(os, "killpg", side_effect=AssertionError("completed group signalled")):
            self.cleanup_orphaned_groups()

    def test_outer_termination_retains_edits_and_logs_and_stops_descendant(self):
        p = self.launch()
        self.worker_ready()
        rd = self.run_dir()
        self.assertIn("AGY_RUN ", (self.root / "tool.err").read_text())
        self.assertEqual((self.root / "tool.out").read_text(), "")
        p.terminate()
        self.assertEqual(p.wait(timeout=6), 143)
        self.assertEqual((rd / "state").read_text().strip(), "interrupted")
        self.assertEqual((rd / "interruption").read_text().strip(), "TERM")
        self.assertEqual((rd / "exit_code").read_text().strip(), "143")
        self.assertIn("partial reply", (rd / "stdout").read_text())
        self.assertIn("executor diagnostic", (rd / "stderr").read_text())
        self.assertIn("useful edit", (self.root / "completed-edit.txt").read_text())
        self.assertEqual((self.root / "invocations").read_text(), "main\n")
        self.assert_writer_stopped()

    def test_sigkill_keeps_preexisting_diagnostics_without_false_completion(self):
        p = self.launch()
        self.worker_ready()
        rd = self.run_dir()
        p.kill()
        self.assertEqual(p.wait(timeout=2), -signal.SIGKILL)
        self.assertIn("partial reply", (rd / "stdout").read_text())
        self.assertEqual((rd / "state").read_text().strip(), "running")
        self.assertFalse((rd / "exit_code").exists())
        # Reproduce the macOS CI failure deterministically: a second signal to
        # the group would raise EPERM after the first successful SIGKILL. Exercise
        # the same cleanup path here and in tearDown, without masking real errors.
        with mock.patch.object(os, "killpg", side_effect=PermissionError("live group denied")):
            with self.assertRaises(PermissionError):
                self.cleanup_orphaned_groups()

        killpg = os.killpg
        signalled = set()

        def kill_once(group, sig):
            if group in signalled:
                raise PermissionError("process group already cleaned")
            signalled.add(group)
            return killpg(group, sig)

        with mock.patch.object(os, "killpg", side_effect=kill_once) as send_signal:
            self.cleanup_orphaned_groups()
            self.cleanup_orphaned_groups()
            send_signal.assert_called_once_with(int((rd / "child_pid").read_text()), signal.SIGKILL)

    def test_sigint_also_cleans_up_and_records_interruption(self):
        p = self.launch()
        self.worker_ready()
        p.send_signal(signal.SIGINT)
        self.assertEqual(p.wait(timeout=6), 130)
        self.assertEqual((self.run_dir() / "interruption").read_text().strip(), "INT")
        self.assert_writer_stopped()

    def test_probe_interruption_is_also_recorded(self):
        p = self.launch("probe_hang", env=dict(self.env, AGY_STRUCTURED_OUTPUT="on"))
        self.eventually(lambda: (self.root / "probe-ready").exists())
        rd = self.run_dir()
        p.terminate()
        self.assertEqual(p.wait(timeout=6), 143)
        self.assertEqual((rd / "state").read_text().strip(), "interrupted")
        self.assertFalse((self.root / "invocations").exists())

    def test_partial_timeout_is_failed_but_useful_output_and_edits_survive(self):
        result = self.call("--timeout", "1s", "task", env=dict(self.env, LIFECYCLE_CASE="partial_timeout"))
        self.assertEqual(result.returncode, 12, result.stderr)
        self.assertEqual(result.stdout, "partial reply\n")
        rd = self.run_dir()
        self.assertEqual((rd / "state").read_text().strip(), "failed")
        self.assertIn("TIMEOUT", (rd / "events.log").read_text())
        self.assertTrue((self.root / "completed-edit.txt").exists())

    def test_wall_clock_guard_stops_worker_and_preserves_partial_files(self):
        if not (shutil.which("timeout") or shutil.which("gtimeout")):
            self.skipTest("no GNU timeout/gtimeout")
        result = self.call("--timeout", "1s", "task", env=dict(self.env, LIFECYCLE_CASE="hang"))
        self.assertEqual(result.returncode, 12, result.stderr)
        rd = self.run_dir()
        self.assertIn("partial reply", (rd / "stdout").read_text())
        self.assertEqual((rd / "exit_code").read_text().strip(), "12")
        self.assert_writer_stopped()

    def test_cancellation_without_gnu_timeout_still_cleans_up(self):
        isolated = self.root / "no-timeout-bin"
        isolated.mkdir()
        for name in ("bash", "python3", "dirname", "mktemp", "mkdir", "date", "cat",
                     "sed", "tr", "cut", "grep", "uname", "sleep"):
            (isolated / name).symlink_to(shutil.which(name))
        (isolated / "agy").symlink_to(self.agy)
        p = self.launch(env=dict(self.env, PATH=str(isolated)))
        self.worker_ready()
        rd = self.run_dir()
        self.assertFalse(json.loads((rd / "run.json").read_text())["wall_clock_guard_available"])
        p.terminate()
        self.assertEqual(p.wait(timeout=6), 143)
        self.assert_writer_stopped()

    def test_job_cancel_collects_interruption_only_after_worker_cleanup(self):
        env = dict(self.env, LIFECYCLE_CASE="hang")
        result = subprocess.run([str(JOB), "start", "--timeout", "15m", "task"],
                                env=env, cwd=self.root, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        job_id = result.stdout.strip()
        self.worker_ready()
        status = subprocess.run([str(JOB), "status", job_id], env=env, cwd=self.root,
                                capture_output=True, text=True, timeout=3)
        self.assertEqual(status.returncode, 0)
        record = next(line.strip()[4:] for line in status.stdout.splitlines()
                      if line.strip().startswith("run="))
        self.assertEqual(json.loads(record)["log_dir"], str(self.run_dir()))
        result = subprocess.run([str(JOB), "cancel", job_id], env=env, cwd=self.root,
                                capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("rc=143", result.stdout)
        jd = Path(env["ANTIGRAVITY_JOBS"]) / job_id
        self.assertEqual((jd / "rc").read_text().strip(), "143")
        self.assertEqual((self.run_dir() / "state").read_text().strip(), "interrupted")
        self.assert_writer_stopped()
        repeated = subprocess.run([str(JOB), "cancel", job_id], env=env, cwd=self.root,
                                  capture_output=True, text=True, timeout=3)
        self.assertEqual(repeated.returncode, 0)
        self.assertEqual(repeated.stdout.strip(), "not running")


if __name__ == "__main__":
    unittest.main(verbosity=2)
