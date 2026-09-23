# shellcheck shell=sh
#
# Antigravity plugin configuration for Kimi Code.
#
# Claude Code exported plugin userConfig to scripts as CLAUDE_PLUGIN_OPTION_*;
# Kimi Code has no settings bridge, so configuration lives in a plain KEY=VALUE
# file sourced by this loader:
#
#   ${AGY_CONFIG:-${KIMI_CODE_HOME:-$HOME/.kimi-code}/antigravity.conf}
#
# Precedence (lowest wins last): caller's inline defaults < config file < environment.
# A variable already set in the environment is never overridden by the file.
#
# Recognised keys (all optional; the wrapper scripts carry their own defaults):
#   AGY_DEFAULT_TIER        flash | flash-lo | pro        (default: flash)
#   AGY_TIMEOUT             default delegation timeout     (default: 5m)
#   AGY_DEFAULT_MODEL       exact agy model name           (default: tier mapping)
#   AGY_TIER_FLASH          model override for flash tier
#   AGY_TIER_FLASH_LO       model override for flash-lo tier
#   AGY_TIER_PRO            model override for pro tier
#   AGY_STRUCTURED_OUTPUT   on/off: agy --output-format json (default: on)
#   AGY_DIGEST_WARN_CHARS   digest-size warning threshold  (default: 8000; 0 = off)
#   AGY_DELEGATION_NUDGE    on/off: bulk-work nudge hook   (default: on)
#   AGY_USAGE_LOG           absolute path: append AGY_USAGE/AGY_SIGNAL lines
#
# Usage:  . "$(dirname "$0")/lib-config.sh"

_agy_keys="AGY_DEFAULT_TIER AGY_TIMEOUT AGY_DEFAULT_MODEL AGY_TIER_FLASH AGY_TIER_FLASH_LO AGY_TIER_PRO AGY_STRUCTURED_OUTPUT AGY_DIGEST_WARN_CHARS AGY_DELEGATION_NUDGE AGY_USAGE_LOG"

_agy_cfg="${AGY_CONFIG:-${KIMI_CODE_HOME:-$HOME/.kimi-code}/antigravity.conf}"
if [ -f "$_agy_cfg" ]; then
  # Snapshot env-set values, source the file, then restore so env always wins.
  for _agy_k in $_agy_keys; do
    eval "_agy_env_${_agy_k}=\"\${${_agy_k}-}\""
  done
  # The config file is user-owned data under KIMI_CODE_HOME (same trust level as
  # a shell rc file); it is expected to contain plain KEY=VALUE assignments.
  . "$_agy_cfg"
  for _agy_k in $_agy_keys; do
    eval "_agy_v=\"\${_agy_env_${_agy_k}-}\""
    if [ -n "$_agy_v" ]; then
      eval "${_agy_k}=\"\$_agy_v\""
    fi
    unset "_agy_env_${_agy_k}"
  done
fi
unset _agy_keys _agy_cfg _agy_k _agy_v
