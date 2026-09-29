#!/usr/bin/env bats
# Tests for the keybind parsers + expectation matching (ADR 0152,
# feature-audit/11+). Parsers turn a shipped config into normalized
# `source<TAB>chord<TAB>action` rows; `check` demands an expectation per row.

setup() {
  INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export INSTALLER_DIR
  FIX="$BATS_TEST_DIRNAME/fixtures"
  source "$INSTALLER_DIR/lib/jsonc.sh"
  source "$INSTALLER_DIR/lib/feature-audit/binds.sh"
}

@test "niri parser: one row per bind, single- and multi-line actions" {
  run fa_binds_parse niri "$FIX/niri-binds.kdl"
  [ "$status" -eq 0 ]
  [ "$(wc -l <<<"$output")" -eq 5 ]
  grep -qxF $'niri\tMod+Return\tspawn "kitty"' <<<"$output"
  grep -qxF $'niri\tMod+D\tspawn-sh "noctalia msg panel-toggle launcher"' \
    <<<"$output"
  grep -qxF $'niri\tMod+1\tfocus-workspace 1' <<<"$output"
  grep -qxF $'niri\tXF86AudioMute\tspawn-sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"' \
    <<<"$output"
}

@test "niri parser: the shipped config parses to its binds" {
  run fa_binds_rows niri
  [ "$status" -eq 0 ]
  grep -qxF $'niri\tMod+X\tclose-window' <<<"$output"
  [ "$(wc -l <<<"$output")" -gt 100 ]
}

@test "plan: chord match wins over action glob; {arg} substitutes" {
  cat > "$BATS_TEST_TMPDIR/b.jsonc" <<'J'
{ "expect": [
  { "action": "focus-workspace *", "effect": "workspace", "arg": "{arg}" },
  { "chord": "Mod+Shift+E", "effect": "session-ends", "session_ending": true },
  { "action": "spawn \"kitty\"", "effect": "window-opens", "arg": "kitty" }
] }
J
  run fa_binds_plan niri "$FIX/niri-binds.kdl" "$BATS_TEST_TMPDIR/b.jsonc"
  [ "$status" -eq 0 ]
  jq -e 'select(.chord == "Mod+1") | .effect == "workspace" and .arg == "1"' \
    <<<"$output"
  jq -e 'select(.chord == "Mod+Shift+E") | .session_ending == true' \
    <<<"$output"
  jq -e 'select(.chord == "Mod+D") | .effect == null' <<<"$output"
}

@test "untested: rows with no expectation are listed" {
  echo '{ "expect": [ { "action": "focus-workspace *", "effect": "workspace",
    "arg": "{arg}" } ] }' > "$BATS_TEST_TMPDIR/b.jsonc"
  run fa_binds_untested niri "$FIX/niri-binds.kdl" "$BATS_TEST_TMPDIR/b.jsonc"
  [ "$(wc -l <<<"$output")" -eq 4 ]
  grep -q 'Mod+Return' <<<"$output"
  ! grep -q 'Mod+1' <<<"$output"
}

@test "hyprland parser: locals, concatenation, for-loops, opts" {
  run fa_binds_parse hyprland "$FIX/hypr-binds.lua"
  [ "$status" -eq 0 ]
  grep -qxF $'hyprland\tSuper+Return\texec_cmd("kitty")' <<<"$output"
  grep -qxF $'hyprland\tSuper+Shift+E\texit()' <<<"$output"
  grep -qxF $'hyprland\tCtrl+Alt+Delete\texit()' <<<"$output"
  grep -qxF $'hyprland\tSuper+left\tfocus({ direction = "left" })' <<<"$output"
  grep -qxF $'hyprland\tSuper+1\tfocus({ workspace = 1 })' <<<"$output"
  grep -qxF $'hyprland\tSuper+2\tfocus({ workspace = 2 })' <<<"$output"
  grep -qxF $'hyprland\tSuper+mouse:272\twindow.drag()' <<<"$output"
  grep -qxF $'hyprland\tXF86AudioMute\texec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")' <<<"$output"
  [ "$(wc -l <<<"$output")" -eq 8 ]
}

@test "kde parser: every active shortcut of every component, none skipped" {
  run fa_binds_parse kde "$FIX/kglobalshortcutsrc"
  [ "$status" -eq 0 ]
  grep -qxF $'kde\tAlt+F4\tkwin/Window Close' <<<"$output"
  grep -qxF $'kde\tMeta+X\tkwin/Window Close' <<<"$output"
  grep -qxF $'kde\tMeta+W\tkwin/Overview' <<<"$output"
  grep -qxF $'kde\tMeta+Plus\tkwin/view_zoom_in' <<<"$output"
  grep -qxF $'kde\tMeta+=\tkwin/view_zoom_in' <<<"$output"
  grep -qxF $'kde\tMeta\tplasmashell/activate application launcher' <<<"$output"
  ! grep -q 'Cycle Overview' <<<"$output"
  [ "$(wc -l <<<"$output")" -eq 7 ]
}

@test "hyprland + kde: shipped configs parse" {
  run fa_binds_rows hyprland
  [ "$status" -eq 0 ]
  grep -qxF $'hyprland\tSuper+X\twindow.close()' <<<"$output"
  run fa_binds_rows kde
  [ "$status" -eq 0 ]
  grep -qxF $'kde\tMeta+X\tkwin/Window Close' <<<"$output"
}

@test "plan: {num} substitutes the action's first number" {
  echo '{ "expect": [ { "action": "focus({ workspace = *", "effect":
    "workspace", "arg": "{num}" } ] }' > "$BATS_TEST_TMPDIR/b.jsonc"
  run fa_binds_plan hyprland "$FIX/hypr-binds.lua" "$BATS_TEST_TMPDIR/b.jsonc"
  jq -e 'select(.chord == "Super+2") | .arg == "2"' <<<"$output"
}
