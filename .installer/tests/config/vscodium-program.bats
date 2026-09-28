#!/usr/bin/env bats
# dev/vscodium program — the VSCodium Config, opt-in parity twin of the Neovim
# Config (ADR 0148). Static seam like nvim-program.bats: assert the COMMITTED
# program, its single-source home/ settings and the extension list — no install
# run. Config Apply places home/ (ADR 0134); install.sh installs the package +
# extensions only.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."        # .installer/tests/config → repo root
  PROG="$REPO/.installer/programs/dev/vscodium"
  CFG="$PROG/config.jsonc"
  INSTALL="$PROG/install.sh"
  EXTS="$PROG/extensions.txt"
  USERDIR="$PROG/home/.config/VSCodium/User"
  SETTINGS="$USERDIR/settings.json"
  KEYS="$USERDIR/keybindings.json"
  UCORE="$REPO/.installer/users/core/profile.jsonc"
  # shellcheck source=../../lib/jsonc.sh
  source "$REPO/.installer/lib/jsonc.sh"
}

# setting <jq-path> → the settings.json value (JSON-encoded).
setting() { jsonc_strip "$SETTINGS" | jq -c "$1"; }

# ext_ids → the extension list, comments and blanks dropped.
ext_ids() { grep -vE '^[[:space:]]*(#|$)' "$EXTS"; }

# ── program definition ───────────────────────────────────────────────────────

@test "dev/vscodium config.jsonc declares an opt-in user-kind program" {
  [ -f "$CFG" ]
  jsonc_strip "$CFG" | jq -e '.name == "vscodium" and .kind == "user"'
  jsonc_strip "$CFG" | jq -e '.stow_opt_in == true'   # ADR 0148
}

@test "VSCodium is opt-in: not served by User Core" {
  ! grep -q '"vscodium"' "$UCORE"
}

@test "install.sh has the mandated shape and starts no service" {
  [ -f "$INSTALL" ]
  run bash -c "grep -vE '^[[:space:]]*(#|\$)' '$INSTALL' | head -2"
  [[ "${lines[0]}" == "set -Eeuo pipefail" ]]
  [[ "${lines[1]}" == trap* ]]
  grep -q 'print_status success' "$INSTALL"
  ! grep -qE 'systemctl (start|restart)' "$INSTALL"
}

@test "install.sh installs vscodium-bin and does NOT seed home/ (ADR 0134)" {
  grep -q -- '--needed vscodium-bin' "$INSTALL"
  ! grep -q '/home/\.' "$INSTALL"
  ! grep -q 'etc/skel' "$INSTALL"
}

@test "install.sh installs the extension list, additive only" {
  grep -q 'extensions.txt' "$INSTALL"
  grep -q -- '--install-extension' "$INSTALL"
  ! grep -q -- '--uninstall-extension' "$INSTALL"
}

@test "the Open VSX-only rule holds: no MS Marketplace anywhere (ADR 0148)" {
  ! grep -rqiE 'marketplace\.visualstudio|vscodium-marketplace' "$PROG"
}

# ── extension list ───────────────────────────────────────────────────────────

@test "extension IDs are bare publisher.name — unpinned (ADR 0148)" {
  [ -f "$EXTS" ]
  run ext_ids
  [ "${#lines[@]}" -gt 0 ]
  local id
  for id in "${lines[@]}"; do
    [[ "$id" =~ ^[A-Za-z0-9-]+\.[A-Za-z0-9._-]+$ ]]
    [[ "$id" != *@* ]]
  done
}

@test "extension list has no duplicates (case-insensitive)" {
  [ -z "$(ext_ids | tr 'A-Z' 'a-z' | sort | uniq -d)" ]
}

@test "the list carries VSCodeVim and the catppuccin theme + icons" {
  ext_ids | grep -qx 'vscodevim.vim'
  ext_ids | grep -qx 'catppuccin.catppuccin-vsc'
  ext_ids | grep -qx 'catppuccin.catppuccin-vsc-icons'
}

# ── single-source settings (ADR 0134) ────────────────────────────────────────

@test "settings.json and keybindings.json parse" {
  jsonc_strip "$SETTINGS" | jq -e 'type == "object"'
  jsonc_strip "$KEYS" | jq -e 'type == "array"'
}

@test "look: Catppuccin Mocha, sapphire accent, no black overrides" {
  [ "$(setting '."workbench.colorTheme"')" = '"Catppuccin Mocha"' ]
  [ "$(setting '."catppuccin.accentColor"')" = '"sapphire"' ]
  [ "$(setting '."catppuccin.colorOverrides"')" = 'null' ]
  [ "$(setting '."workbench.iconTheme"')" = '"catppuccin-mocha"' ]
}

@test "font is the seeded FiraCode Nerd Font 12 with ligatures" {
  [ "$(setting '."editor.fontFamily"')" = '"FiraCode Nerd Font"' ]
  [ "$(setting '."terminal.integrated.fontFamily"')" = '"FiraCode Nerd Font"' ]
  [ "$(setting '."editor.fontSize"')" = '12' ]
  [ "$(setting '."editor.fontLigatures"')" = 'true' ]
}

@test "layout: sidebar right, no startup editor, sticky scroll" {
  [ "$(setting '."workbench.sideBar.location"')" = '"right"' ]
  [ "$(setting '."workbench.startupEditor"')" = '"none"' ]
  [ "$(setting '."editor.stickyScroll.enabled"')" = 'true' ]
}

@test "VSCodeVim basics: Space leader, jj, clipboard, C-a/f/p passed" {
  [ "$(setting '."vim.leader"')" = '"<space>"' ]
  setting '."vim.insertModeKeyBindings"' \
    | jq -e 'any(.[]; .before == ["j","j"] and .after == ["<Esc>"])'
  [ "$(setting '."vim.useSystemClipboard"')" = 'true' ]
  [ "$(setting '."editor.lineNumbers"')" = '"relative"' ]
  setting '."vim.handleKeys"' \
    | jq -e '.["<C-a>"] == false and .["<C-f>"] == false
             and .["<C-p>"] == false'
}

@test "a no-name ./stow-configs.sh sweep skips vscodium (ADR 0148)" {
  source "$REPO/.installer/lib/config/config-apply.sh"
  local root="$REPO/.installer/programs"
  ca_stow_opt_in_list "$root" | jq -e 'index("vscodium") != null'
  ca_stow_selection "$(ca_ships_home_list "$root")" '[]' '[]' \
    "$(ca_stow_opt_in_list "$root")" | jq -e 'index("vscodium") == null'
}
