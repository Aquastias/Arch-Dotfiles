# shellcheck shell=bash
# Feature Audit desktop probe for Hyprland (ADR 0152): runs inside the live
# Hyprland session as the desktop user (sessions phase).
[[ "$FA_SESSION" == Hyprland ]] || { fa_skip hyprland-session "not the running session"; return 0; }
HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-$(find "$XDG_RUNTIME_DIR/hypr" -mindepth 1 -maxdepth 1 -printf "%f\n" 2>/dev/null | head -1)}"
export HYPRLAND_INSTANCE_SIGNATURE
fa_check hyprland-ipc "hyprctl answers" hyprctl -j version
_fa_hypr_errors() {
  local e; e="$(hyprctl -j configerrors 2>/dev/null | jq -r '.[] | select(. != "")')"
  [[ -z "$e" ]] || { printf '%s\n' "$e"; return 1; }
}
fa_check hyprland-config "no Hyprland config errors" _fa_hypr_errors
# shellcheck source=/dev/null # staged beside this probe (audit-fixtures)
. "$FA_DIR/audit-fixtures/audit-wlroots.sh"
