#!/usr/bin/env bash
# Claude Code PreToolUse hook (ADR 0156): block a foreground Bash `sleep` of
# 60 s or more. Sessions spent ~44 h in `sleep N; tail <task output>` polls,
# though a background task already re-invokes the agent when it exits. Short
# sleeps inside an `until` loop and anything run_in_background pass.
set -euo pipefail

input="$(cat)"
read_field() { jq -r "$1" <<<"$input" 2>/dev/null || true; }

[[ "$(read_field '.tool_name')" == Bash ]] || exit 0
[[ "$(read_field '.tool_input.run_in_background // false')" == true ]] \
  && exit 0

command_text="$(read_field '.tool_input.command // ""')"
longest="$(awk '
  {
    while (match($0, /(^|[^[:alnum:]_])sleep +[0-9]+[smh]?/)) {
      token = substr($0, RSTART, RLENGTH)
      sub(/.*sleep +/, "", token)
      seconds = token + 0
      if (token ~ /m$/) seconds *= 60
      if (token ~ /h$/) seconds *= 3600
      if (seconds > best) best = seconds
      $0 = substr($0, RSTART + RLENGTH)
    }
  }
  END { print best + 0 }' <<<"$command_text")"

(( longest < 60 )) && exit 0

cat >&2 <<EOF
Blocked: foreground \`sleep ${longest}\` polling. A run_in_background task
notifies you when it exits — end the turn and wait for that. For external
state, use \`timeout <s> bash -c 'until <check>; do sleep 5; done'\`.
EOF
exit 2
