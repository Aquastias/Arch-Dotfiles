# shellcheck shell=bash
# Feature Audit desktop probe for niri (ADR 0152): runs inside the live niri
# session as the desktop user (sessions phase). Shared wlroots checks live in
# ../audit-wlroots.sh (staged as audit-fixtures/audit-wlroots.sh).
if [[ "$FA_SESSION" != niri ]]; then
  fa_skip niri-session "not the running session"; return 0
fi
fa_check niri-config "niri validates the shipped config" niri validate
fa_check niri-ipc "niri IPC answers" niri msg -j version
# shellcheck source=/dev/null
. "$FA_DIR/audit-fixtures/audit-wlroots.sh"
