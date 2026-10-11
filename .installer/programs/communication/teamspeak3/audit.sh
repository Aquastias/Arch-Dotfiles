# shellcheck shell=bash
# Feature Audit probe for teamspeak3 (ADR 0152; contract: PROGRAM_SPEC.md).
# Connecting needs a TeamSpeak server (unverifiable): launch is proven.
feature_audit_require_package teamspeak3 teamspeak3 || return 0
feature_audit_as_user || return 0
if [[ "$FA_SESSION" == none || -z "${WAYLAND_DISPLAY:-}" ]]; then
  feature_audit_skip teamspeak3-launch "no live session"; return 0
fi
_probe_ts3() {
  setsid -f teamspeak3 >/tmp/fa-ts3.log 2>&1; sleep 8
  pgrep -f ts3client >/dev/null; local rc=$?
  pkill -f ts3client; return "$rc"
}
feature_audit_check teamspeak3-launch "client starts and stays up" _probe_ts3
