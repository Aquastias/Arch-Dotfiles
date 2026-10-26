#!/usr/bin/env bats
# dev/emacs program — the Emacs Config, opt-in Doom Emacs parity twin of the
# Neovim Config (ADR 0160). Static seam like vscodium-program.bats: assert the
# COMMITTED program, its pin and its single-source home/ Doom config — no
# install run, no Emacs runtime. Config Apply places home/ (ADR 0134); the
# Post-Config Hook runs Doom's install against it.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."   # .installer/tests/config → repo root
  PROG="$REPO/.installer/programs/dev/emacs"
  CFG="$PROG/config.jsonc"
  INSTALL="$PROG/install.sh"
  HOOK="$PROG/post-config.sh"
  PIN="$PROG/doom-ref"
  DOOMDIR="$PROG/home/.config/doom"
  UCORE="$REPO/.installer/users/core/profile.jsonc"
  OPERATOR="$REPO/.installer/users/aquastias/profile.jsonc"
  # shellcheck source=../../lib/jsonc.sh
  source "$REPO/.installer/lib/jsonc.sh"
}

# data_rows FILE → the rows of a data file, `#` comments and blanks dropped.
data_rows() { grep -vE '^[[:space:]]*(#|$)' "$1"; }

# code_lines FILE → the file's lines with comments and blanks dropped.
code_lines() { grep -vE '^[[:space:]]*(#|$)' "$1"; }

# ── program definition ───────────────────────────────────────────────────────

@test "dev/emacs config.jsonc declares an opt-in user-kind program" {
  [ -f "$CFG" ]
  jsonc_strip "$CFG" | jq -e '.name == "emacs" and .kind == "user"'
  jsonc_strip "$CFG" | jq -e '.stow_opt_in == true'   # ADR 0160
}

@test "Emacs is opt-in: not in User Core, listed by the operator" {
  ! grep -q '"emacs"' "$UCORE"
  jsonc_strip "$OPERATOR" | jq -e '.programs | index("emacs") != null'
}

@test "install.sh has the mandated shape and starts no service" {
  [ -f "$INSTALL" ]
  run bash -c "grep -vE '^[[:space:]]*(#|\$)' '$INSTALL' | head -2"
  [[ "${lines[0]}" == "set -Eeuo pipefail" ]]
  [[ "${lines[1]}" == trap* ]]
  grep -q 'print_status success' "$INSTALL"
  ! grep -qE 'systemctl (start|restart|enable)' "$INSTALL"
}

@test "install.sh installs emacs-wayland from the repos, does NOT seed home/" {
  grep -qE -- '--needed emacs-wayland( |$)' "$INSTALL"
  run bash -c "$(declare -f code_lines); code_lines '$INSTALL' \
    | grep -E 'home/|\.config/doom|etc/skel|/root'"
  [ -z "$output" ]
}

# ── pinned Doom (ADR 0160) ───────────────────────────────────────────────────

@test "the pin is exactly one 40-hex Doom commit" {
  [ -f "$PIN" ]
  run data_rows "$PIN"
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" =~ ^[0-9a-f]{40}$ ]]
}

@test "install.sh clones Doom core at the pin, re-pins, never deletes it" {
  grep -q 'doom-ref' "$INSTALL"
  grep -q 'github.com/doomemacs/core' "$INSTALL"
  grep -qE 'checkout .*(FETCH_HEAD|\$\{?pin)' "$INSTALL"
  run bash -c "$(declare -f code_lines); code_lines '$INSTALL' \
    | grep -E 'rm -r|rm -fr|rm -rf'"
  [ -z "$output" ]
}

# ── Post-Config Hook: Doom's install against the placed config ───────────────

@test "post-config.sh has the mandated shape" {
  [ -f "$HOOK" ]
  run bash -c "grep -vE '^[[:space:]]*(#|\$)' '$HOOK' | head -2"
  [[ "${lines[0]}" == "set -Eeuo pipefail" ]]
  [[ "${lines[1]}" == trap* ]]
  ! code_lines "$HOOK" | grep -qE 'systemctl|sudo'   # runs with no sudo
}

@test "post-config.sh runs Doom's install unattended, without an env file" {
  grep -qE 'bin/doom"? --force install --no-env' "$HOOK"
}

@test "post-config.sh skips (warns) when the Doom config was not placed" {
  grep -q 'init.el' "$HOOK"
  [ "$(grep -c 'print_status warning' "$HOOK")" -ge 2 ]
}

# ── the Doom config: modules and look (ADR 0160) ─────────────────────────────

# elisp FILE → the file with `;` comments stripped (no string has a `;`).
elisp() { awk '{ sub(/;.*/, ""); if ($0 ~ /[^[:space:]]/) print }' "$1"; }

# module_enabled <module-form> → status 0 when init.el's doom! block enables it
# (e.g. `(evil +everywhere)` or `vertico`) on an uncommented line.
module_enabled() {
  elisp "$DOOMDIR/init.el" | grep -qF -- "$1"
}

@test "the Doom config is three files: init.el, config.el, packages.el" {
  [ -f "$DOOMDIR/init.el" ] && [ -f "$DOOMDIR/config.el" ]
  [ -f "$DOOMDIR/packages.el" ]
  elisp "$DOOMDIR/init.el" | grep -q '(doom!'
}

@test "evil everywhere with Doom's SPC leader bindings" {
  module_enabled '(evil +everywhere)'
  module_enabled '(default +bindings +smartparens)'
  ! elisp "$DOOMDIR/config.el" | grep -q 'doom-leader-key'
}

@test "font is the seeded FiraCode Nerd Font at 12pt" {
  elisp "$DOOMDIR/config.el" \
    | grep -qF '(font-spec :family "FiraCode Nerd Font" :size 12.0)'
  module_enabled 'ligatures'
}

@test "static look: Catppuccin Mocha from catppuccin-theme" {
  elisp "$DOOMDIR/packages.el" | grep -qF '(package! catppuccin-theme'
  elisp "$DOOMDIR/config.el" | grep -qF "(setq catppuccin-flavor 'mocha)"
  elisp "$DOOMDIR/config.el" | grep -qF "(setq doom-theme 'catppuccin)"
}

@test "sapphire accent overlays the faces nvim overlays" {
  local face
  for face in cursor show-paren-match isearch lazy-highlight vertico-current \
    corfu-current dired-directory; do
    elisp "$DOOMDIR/config.el" | grep -qE "\($face .*#74c7ec" \
      || { echo "no sapphire on $face"; false; }
  done
}

@test "a no-name ./stow-configs.sh sweep skips emacs (ADR 0160)" {
  source "$REPO/.installer/lib/config/config-apply.sh"
  local root="$REPO/.installer/programs"
  config_apply_stow_opted_in_programs "$root" | jq -e 'index("emacs") != null'
  config_apply_stow_selection "$(config_apply_ships_home_list "$root")" \
    '[]' '[]' "$(config_apply_stow_opted_in_programs "$root")" \
    | jq -e 'index("emacs") == null'
}
