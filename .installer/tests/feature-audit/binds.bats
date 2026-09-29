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
