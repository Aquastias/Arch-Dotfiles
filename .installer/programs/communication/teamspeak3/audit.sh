# shellcheck shell=bash
# Feature Audit probe for teamspeak3 (ADR 0152; contract: PROGRAM_SPEC.md).
# Connecting needs a TeamSpeak server (unverifiable): launch is proven.
fa_require_pkg teamspeak3 teamspeak3 || return 0
fa_as_user || return 0
if [[ "$FA_SESSION" == none || -z "${WAYLAND_DISPLAY:-}" ]]; then
  fa_skip teamspeak3-launch "no live session"; return 0
fi
_fa_ts3() {
  setsid -f teamspeak3 >/tmp/fa-ts3.log 2>&1; sleep 8
  pgrep -f ts3client >/dev/null; local rc=$?
  pkill -f ts3client; return "$rc"
}
fa_check teamspeak3-launch "client starts and stays up" _fa_ts3
