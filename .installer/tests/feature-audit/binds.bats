#!/usr/bin/env bats
# Tests for the keybind parsers + expectation matching (ADR 0152,
# feature-audit/11+). Parsers turn a shipped config into normalized
# `source<TAB>chord<TAB>action` rows; `check` demands an expectation per row.

load ../lib/text-helpers
load ../lib/json-helpers

setup() {
  INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export INSTALLER_DIR
  FIX="$BATS_TEST_DIRNAME/fixtures"
  source "$INSTALLER_DIR/lib/jsonc.sh"
  source "$INSTALLER_DIR/lib/feature-audit/binds.sh"
}

@test "niri parser: one row per bind, single- and multi-line actions" {
  run feature_audit_binds_parse niri "$FIX/niri-binds.kdl"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 5 ]
  text_has_line "$output" $'niri\tMod+Return\tspawn "kitty"'
  text_has_line "$output" $'niri\tMod+D\tspawn-sh "noctalia msg panel-toggle launcher"'
  text_has_line "$output" $'niri\tMod+1\tfocus-workspace 1'
  local mute='spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"'
  text_has_line "$output" "niri"$'\t'"XF86AudioMute"$'\t'"$mute"
}

@test "niri parser: the shipped config parses to its binds" {
  run feature_audit_binds_rows niri
  [ "$status" -eq 0 ]
  text_has_line "$output" $'niri\tMod+X\tclose-window'
  [ "${#lines[@]}" -gt 100 ]
}

# Umbriel (ADR 0159): TOML [keybinds] — plain, inline-table and sub-table forms.
@test "umbriel parser: one row per bind across every TOML bind form" {
  run feature_audit_binds_parse umbriel "$FIX/umbriel-binds.toml"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 6 ]
  text_has_line "$output" $'umbriel\tMod+Return\tspawn kitty'
  text_has_line "$output" $'umbriel\tMod+X\twindow-close'
  text_has_line "$output" $'umbriel\tMod+1\tworkspace-switch 1'
  text_has_line "$output" $'umbriel\tMod+Escape\tshortcuts-inhibit-toggle'
  local mute='spawn wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle'
  text_has_line "$output" "umbriel"$'\t'"XF86AudioMute"$'\t'"$mute"
  local shot='spawn grim -g "$(umbriel windows --json | jq -r '
  shot+="'.[] | select(.active)')\" out.png"
  text_has_line "$output" "umbriel"$'\t'"Shift+Print"$'\t'"$shot"
}

@test "umbriel parser: the shipped config parses to its binds" {
  run feature_audit_binds_rows umbriel
  [ "$status" -eq 0 ]
  text_has_line "$output" $'umbriel\tMod+X\twindow-close'
  [ "${#lines[@]}" -gt 100 ]
}

@test "plan: chord match wins over action glob; {arg} substitutes" {
  cat > "$BATS_TEST_TMPDIR/b.jsonc" <<'J'
{ "expect": [
  { "action": "focus-workspace *", "effect": "workspace", "arg": "{arg}" },
  { "chord": "Mod+Shift+E", "effect": "session-ends", "session_ending": true },
  { "action": "spawn \"kitty\"", "effect": "window-opens", "arg": "kitty" }
] }
J
  run feature_audit_binds_plan niri "$FIX/niri-binds.kdl" "$BATS_TEST_TMPDIR/b.jsonc"
  [ "$status" -eq 0 ]
  output_satisfies 'select(.chord == "Mod+1") | .effect == "workspace" and .arg == "1"'
  output_satisfies 'select(.chord == "Mod+Shift+E") | .session_ending == true'
  output_satisfies 'select(.chord == "Mod+D") | .effect == null'
}

@test "untested: rows with no expectation are listed" {
  echo '{ "expect": [ { "action": "focus-workspace *", "effect": "workspace",
    "arg": "{arg}" } ] }' > "$BATS_TEST_TMPDIR/b.jsonc"
  run feature_audit_binds_untested niri "$FIX/niri-binds.kdl" "$BATS_TEST_TMPDIR/b.jsonc"
  [ "${#lines[@]}" -eq 4 ]
  echo "$output" | grep -q 'Mod+Return'
  ! echo "$output" | grep -q 'Mod+1'
}

@test "hyprland parser: locals, concatenation, for-loops, opts" {
  run feature_audit_binds_parse hyprland "$FIX/hypr-binds.lua"
  [ "$status" -eq 0 ]
  text_has_line "$output" $'hyprland\tSuper+Return\texec_cmd("kitty")'
  text_has_line "$output" $'hyprland\tSuper+Shift+E\texit()'
  text_has_line "$output" $'hyprland\tCtrl+Alt+Delete\texit()'
  text_has_line "$output" $'hyprland\tSuper+left\tfocus({ direction = "left" })'
  text_has_line "$output" $'hyprland\tSuper+1\tfocus({ workspace = 1 })'
  text_has_line "$output" $'hyprland\tSuper+2\tfocus({ workspace = 2 })'
  text_has_line "$output" $'hyprland\tSuper+mouse:272\twindow.drag()'
  text_has_line "$output" $'hyprland\tXF86AudioMute\texec_cmd("wpctl mute")'
  [ "${#lines[@]}" -eq 8 ]
}

@test "kde parser: every active shortcut of every component, none skipped" {
  run feature_audit_binds_parse kde "$FIX/kglobalshortcutsrc"
  [ "$status" -eq 0 ]
  text_has_line "$output" $'kde\tAlt+F4\tkwin/Window Close'
  text_has_line "$output" $'kde\tMeta+X\tkwin/Window Close'
  text_has_line "$output" $'kde\tMeta+W\tkwin/Overview'
  text_has_line "$output" $'kde\tMeta+Plus\tkwin/view_zoom_in'
  text_has_line "$output" $'kde\tMeta+=\tkwin/view_zoom_in'
  text_has_line "$output" $'kde\tMeta\tplasmashell/activate application launcher'
  ! echo "$output" | grep -q 'Cycle Overview'
  [ "${#lines[@]}" -eq 7 ]
}

@test "hyprland + kde: shipped configs parse" {
  run feature_audit_binds_rows hyprland
  [ "$status" -eq 0 ]
  text_has_line "$output" $'hyprland\tSuper+X\twindow.close()'
  run feature_audit_binds_rows kde
  [ "$status" -eq 0 ]
  text_has_line "$output" $'kde\tMeta+X\tkwin/Window Close'
}

@test "plan: {num} substitutes the action's first number" {
  echo '{ "expect": [ { "action": "focus({ workspace = *", "effect":
    "workspace", "arg": "{num}" } ] }' > "$BATS_TEST_TMPDIR/b.jsonc"
  run feature_audit_binds_plan hyprland "$FIX/hypr-binds.lua" "$BATS_TEST_TMPDIR/b.jsonc"
  output_satisfies 'select(.chord == "Super+2") | .arg == "2"'
}

@test "nvim parser: map/keymap.set calls and lazy keys specs" {
  run feature_audit_binds_parse nvim "$FIX/nvim-keys.lua"
  [ "$status" -eq 0 ]
  text_has_line "$output" $'nvim\t<leader>w\tn Write buffer'
  text_has_line "$output" $'nvim\t<C-/>\tn,t Toggle terminal'
  text_has_line "$output" $'nvim\tJ\tv Move selection down'
  text_has_line "$output" $'nvim\t<leader>xx\tn Diags'
  text_has_line "$output" $'nvim\ts\tn,x Flash'
  # a dynamically built lhs is left to the live keymap dump
  ! echo "$output" | grep -q $'\t<leader>\t'
  [ "${#lines[@]}" -eq 5 ]
}

@test "program sources: nvim binds are driven by the nvim probe" {
  run feature_audit_binds_program_sources nvim
  [ "$output" = nvim ]
  run feature_audit_binds_session nvim
  [ "$output" = "-" ]
}

@test "kitty parser: map lines, kitty_mod = Ctrl+Shift" {
  run feature_audit_binds_parse kitty "$FIX/kitty-keys.conf"
  [ "$status" -eq 0 ]
  text_has_line "$output" $'kitty\tCtrl+Shift+t\tnew_tab_with_cwd'
  text_has_line "$output" $'kitty\tCtrl+Alt+enter\tlaunch --cwd=current'
  [ "${#lines[@]}" -eq 2 ]
}

@test "zsh parser: explicit bindkey lines, not keymap switches" {
  run feature_audit_binds_parse zsh "$FIX/zshrc"
  [ "$status" -eq 0 ]
  text_has_line "$output" $'zsh\t^[[1;5C\tmain forward-word'
  text_has_line "$output" $'zsh\t^R\tviins history-incremental-search-backward'
  [ "${#lines[@]}" -eq 2 ]
}

@test "plan: a source with no binds plans nothing, without error" {
  : > "$BATS_TEST_TMPDIR/empty.zshrc"
  echo '{ "expect": [] }' > "$BATS_TEST_TMPDIR/b.jsonc"
  run feature_audit_binds_plan zsh "$BATS_TEST_TMPDIR/empty.zshrc" \
    "$BATS_TEST_TMPDIR/b.jsonc"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "plan: a chord+action expectation holds only for that action" {
  # Regression (Audit Run 20260929): {chord K, action "n Hover"} also claimed
  # visual-mode K (Move selection up) and judged it as an LSP hover.
  cat > "$BATS_TEST_TMPDIR/k.lua" <<'L'
vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Hover" })
vim.keymap.set("v", "K", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })
L
  cat > "$BATS_TEST_TMPDIR/b.jsonc" <<'J'
{ "expect": [
  { "chord": "K", "action": "n Hover", "effect": "window-opens" },
  { "action": "v Move selection *", "effect": "text-changes" }
] }
J
  run feature_audit_binds_plan nvim "$BATS_TEST_TMPDIR/k.lua" "$BATS_TEST_TMPDIR/b.jsonc"
  [ "$status" -eq 0 ]
  output_satisfies 'select(.action == "n Hover") | .effect == "window-opens"'
  output_satisfies 'select(.action == "v Move selection up") | .effect == "text-changes"'
}

@test "emacs parser: Doom map! state and leader binds, unbinds skipped" {
  run feature_audit_binds_parse emacs "$FIX/emacs-keys.el"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 7 ]
  text_has_line "$output" $'emacs\t]d\tm flymake-goto-next-error'
  text_has_line "$output" $'emacs\ts\tn avy-goto-char-timer'
  text_has_line "$output" $'emacs\tC-SPC\tnv er/expand-region'
  text_has_line "$output" $'emacs\tJ\tv +parity/move-lines-down'
  text_has_line "$output" $'emacs\tSPC w\tleader save-buffer'
  text_has_line "$output" $'emacs\tSPC 1\tleader harpoon-go-to-1'
  text_has_line "$output" $'emacs\tSPC g g\tleader +parity/lazygit'
}

@test "program sources: emacs binds are driven by the emacs probe" {
  run feature_audit_binds_program_sources emacs
  [ "$output" = emacs ]
  run feature_audit_binds_session emacs
  [ "$output" = - ]
}

@test "emacs: every shipped bind has an expectation" {
  run feature_audit_binds_rows emacs
  [ "$status" -eq 0 ]
  text_has_line "$output" $'emacs\tSPC g g\tleader +parity/lazygit'
  run feature_audit_binds_untested emacs
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
