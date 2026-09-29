# shellcheck shell=bash
# Feature Audit desktop probe for Hyprland (ADR 0152): runs inside the live
# Hyprland session as the desktop user (sessions phase). Shared wlroots
# checks: ../audit-wlroots.sh (staged as audit-fixtures/audit-wlroots.sh).
if [[ "$FA_SESSION" != Hyprland ]]; then
  fa_skip hyprland-session "not the running session"; return 0
fi
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  HYPRLAND_INSTANCE_SIGNATURE="$(find "$XDG_RUNTIME_DIR/hypr" -mindepth 1 \
    -maxdepth 1 -printf '%f\n' 2>/dev/null | head -1)"
  export HYPRLAND_INSTANCE_SIGNATURE
fi
fa_check hyprland-ipc "hyprctl answers" hyprctl -j version
_fa_hypr_errors() {
  local e
  e="$(hyprctl -j configerrors 2>/dev/null | jq -r '.[] | select(. != "")')"
  [[ -z "$e" ]] || { printf '%s\n' "$e"; return 1; }
}
fa_check hyprland-config "no Hyprland config errors" _fa_hypr_errors
# shellcheck source=/dev/null
. "$FA_DIR/audit-fixtures/audit-wlroots.sh"
