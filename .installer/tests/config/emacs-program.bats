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

# ── languages on the system toolchain (ADR 0160) ─────────────────────────────

COVERAGE_REL=.installer/programs/dev/emacs/coverage.txt
LANGS_REL=.installer/programs/dev/nvim/home/.config/nvim/lua/config
LANGS_REL=$LANGS_REL/languages.lua   # the Language Registry
FLEET_REL=.installer/hosts/fleet/profile.jsonc

# registry_keys → the Language Registry's language keys (ADR 0141), read from
# nvim's languages.lua with awk — no Lua runtime.
registry_keys() {
  awk '/^local registry = \{/ { on = 1; next }
       on && /^}/ { exit }
       on && match($0, /^  [a-z_]+ = /) {
         k = substr($0, 3); sub(/ = .*/, "", k); print k }' \
    "$REPO/$LANGS_REL"
}

@test "LSP via eglot, flymake checking, format on save without LSP format" {
  module_enabled '(lsp +eglot)'
  module_enabled '(syntax +flymake)'
  module_enabled '(format +onsave)'
  # +lsp would hand formatting to the server, overriding conform's choice.
  ! elisp "$DOOMDIR/init.el" | grep -qE '\(format [^)]*\+lsp'
  ! elisp "$DOOMDIR/init.el" | grep -qE '(^|[[:space:]])debugger'
}

@test "Emacs Coverage Map keys == Language Registry keys (ADR 0160)" {
  diff <(registry_keys | sort) \
    <(data_rows "$REPO/$COVERAGE_REL" | awk '{ print $1 }' | sort -u)
}

@test "every Coverage Map module is enabled and every package declared" {
  local token
  while read -r token; do
    case "$token" in
    :lang/*) elisp "$DOOMDIR/init.el" \
        | grep -qE "(^|[[:space:](])${token#:lang/}([[:space:])]|$)" \
        || { echo "module off: $token"; false; } ;;
    pkg:*) elisp "$DOOMDIR/packages.el" \
        | grep -qF "(package! ${token#pkg:} " \
        || { echo "package missing: $token"; false; } ;;
    builtin:*) ;;
    *) echo "unknown token: $token"; false ;;
    esac
  done < <(data_rows "$REPO/$COVERAGE_REL" \
    | awk '$2 != "n/a" { for (i = 2; i <= NF; i++) print $i }')
}

@test "an n/a Coverage Map row states a reason" {
  run bash -c "$(declare -f data_rows); data_rows '$REPO/$COVERAGE_REL' \
    | awk '\$2 == \"n/a\" && NF < 3'"
  [ -z "$output" ]
}

# Each Registry server → the system binary eglot must launch and the Fleet
# Layer package providing it. phpactor rides dev/nvim's install.
@test "eglot launches every Registry server from the system toolchain" {
  local binary package
  while read -r binary package; do
    elisp "$DOOMDIR/config.el" | grep -qF "\"$binary\"" \
      || { echo "no eglot client for $binary"; false; }
    if [[ "$package" == @nvim:* ]]; then
      grep -q "needed ${package#@nvim:}" \
        "$REPO/.installer/programs/dev/nvim/install.sh"
    else
      grep -q "\"$package\"" "$REPO/$FLEET_REL" \
        || { echo "$package not in the Fleet Layer"; false; }
    fi
  done <<'EOF_'
lua-language-server lua-language-server
basedpyright-langserver basedpyright
nixd nixd
phpactor @nvim:phpactor
svelteserver svelte-language-server
vue-language-server vue-language-server
typescript-language-server typescript-language-server
vscode-json-language-server vscode-langservers-extracted
vscode-css-language-server vscode-langservers-extracted
vscode-html-language-server vscode-langservers-extracted
yaml-language-server yaml-language-server
bash-language-server bash-language-server
gopls gopls
rust-analyzer rust-analyzer
zls zls
clangd clang
EOF_
}

# nvim filetype's Emacs major mode → the apheleia formatter conform's choice
# maps to. Independent of config.el: this is the parity contract.
@test "each Registry formatter is the apheleia formatter for its mode" {
  local mode formatter
  while read -r mode formatter; do
    elisp "$DOOMDIR/config.el" | grep -qF "($mode . $formatter)" \
      || { echo "$mode: want $formatter"; false; }
  done <<'EOF_'
lua-mode stylua
python-mode ruff
nix-mode nixfmt
php-mode phpcbf
js-mode biome
typescript-mode biome
json-mode biome
jsonc-mode biome
css-mode biome
scss-mode prettier-scss
less-css-mode prettier-css
nxml-mode xmllint
web-mode prettier
yaml-mode prettier-yaml
markdown-mode prettier-markdown
sh-mode shfmt
kdl-mode kdlfmt
conf-toml-mode taplo
go-mode gofmt
rustic-mode rustfmt
zig-mode zig-fmt
c-mode clang-format
c++-mode clang-format
EOF_
}

@test "manual-only formatters (shfmt, kdlfmt, taplo) skip format on save" {
  local mode
  for mode in sh-mode kdl-mode conf-toml-mode; do
    elisp "$DOOMDIR/config.el" \
      | awk '/\+format-on-save-disabled-modes/,/\)\)/' | grep -qw "$mode" \
      || { echo "$mode formats on save"; false; }
  done
  [ "$(grep -c "format_on_save = false" "$REPO/$LANGS_REL")" -eq 3 ]
}

@test "linters: ruff for python, biome only where biome.json exists" {
  elisp "$DOOMDIR/packages.el" | grep -qF '(package! flymake-ruff '
  elisp "$DOOMDIR/packages.el" | grep -qF '(package! flymake-biome '
  elisp "$DOOMDIR/config.el" | grep -qF '"biome.json"'
  elisp "$DOOMDIR/config.el" | grep -qF '"biome.jsonc"'
}

@test "]d/[d jump diagnostics, SPC c o organizes imports" {
  elisp "$DOOMDIR/config.el" | grep -qE '"\]d".*flymake-goto-next-error'
  elisp "$DOOMDIR/config.el" | grep -qE '"\[d".*flymake-goto-prev-error'
  elisp "$DOOMDIR/config.el" | grep -qE '"c o".*organize-imports'
}

# ── key parity with the Neovim Config: nvim wins (ADR 0160) ──────────────────

# bound <key> <command> → status 0 when config.el binds the key (a map! key
# string; leader keys space-separated) straight to the named command.
bound() {
  elisp "$DOOMDIR/config.el" | grep -qF "\"$1\" #'$2" \
    || { echo "unbound: $1 → $2"; return 1; }
}

@test "motions: s is avy with evil-snipe off; gs* is surround" {
  elisp "$DOOMDIR/packages.el" | grep -qF '(package! evil-snipe :disable t)'
  bound s avy-goto-char-timer
  bound gsa evil-surround-region
  bound gsd evil-surround-delete
  bound gsr evil-surround-change
}

@test "files: - is dired-jump, SPC e toggles treemacs on the right" {
  module_enabled 'treemacs'
  bound - dired-jump
  bound e +treemacs/toggle
  elisp "$DOOMDIR/config.el" | grep -qF "(setq treemacs-position 'right)"
}

@test "core keys match nvim's keymaps.lua" {
  bound w save-buffer
  bound q evil-quit
  bound '<tab>' next-buffer
  bound '<backtab>' previous-buffer
  bound C-h evil-window-left
  bound C-j evil-window-down
  bound C-k evil-window-up
  bound C-l evil-window-right
  bound 'b d' kill-current-buffer
  bound 'y p' +parity/copy-file-path
  bound J +parity/move-lines-down
  bound K +parity/move-lines-up
  # nvim's SPC p dodges Vim's register-clobbering visual paste; evil can
  # simply not clobber, which leaves Doom's SPC p project prefix intact.
  elisp "$DOOMDIR/config.el" \
    | grep -qF '(setq evil-kill-on-visual-paste nil)'
  bound 'r w' +parity/replace-word
  bound C-SPC er/expand-region
  bound '<backspace>' er/contract-region
  bound C-d +parity/scroll-down-centered
  bound C-u +parity/scroll-up-centered
  bound 'c x' +parity/make-executable
  bound RET eval-buffer
}

@test "find/search keys match nvim's snacks + grug-far maps" {
  bound 'f g' +default/search-project
  bound 'f b' consult-buffer
  bound 'f r' consult-recent-file
  bound 'f h' consult-info
  bound 's s' consult-imenu
  bound 's S' xref-find-apropos
  bound 's c' execute-extended-command
  bound 's k' embark-bindings
  bound 's r' project-query-replace-regexp
}

@test "git keys: lazygit on SPC g g, magit one key away, hunks, history" {
  module_enabled 'magit'
  bound 'g g' +parity/lazygit
  bound 'g l' +parity/lazygit-log
  bound 'g m' magit-status
  bound 'g s' magit-status
  bound 'g d' magit-diff-unstaged
  bound 'g h' magit-log-buffer-file
  bound 'g H' magit-log-current
  bound 'g b' magit-branch-checkout
  bound 'g L' magit-log-all
  bound 'g B' +vc/git-link
  bound 'g t' magit-blame-addition
  bound ']h' +vc-gutter/next-hunk
  bound '[h' +vc-gutter/previous-hunk
}

@test "diagnostics, todo and refactor keys where eglot backs them" {
  bound 'x x' flymake-show-project-diagnostics
  bound 'x X' flymake-show-buffer-diagnostics
  bound 'x t' hl-todo-occur
  bound 'x s' consult-imenu
  bound ']t' hl-todo-next
  bound '[t' hl-todo-previous
  bound 'r e' eglot-code-action-extract
  bound 'r v' eglot-code-action-extract
  bound 'r f' eglot-code-actions
  bound 'r i' eglot-code-action-inline
  bound 'r I' eglot-code-action-inline
  bound 'u h' eglot-inlay-hints-mode
}

@test "harpoon, undo tree and the terminal toggle" {
  elisp "$DOOMDIR/packages.el" | grep -qF '(package! harpoon '
  module_enabled '(undo +tree)'
  module_enabled 'vterm'
  bound a harpoon-add-file
  bound C-e harpoon-toggle-quick-menu
  local i
  for i in 1 2 3 4 5 6 7 8 9; do bound "$i" "harpoon-go-to-$i"; done
  bound U vundo
  bound C-/ +vterm/toggle
  elisp "$DOOMDIR/config.el" | grep -qF '(setq vterm-always-compile-module t)'
}

@test "install.sh adds vterm's build deps (Doom's vterm README)" {
  # join backslash-continued lines, so a package on line two still counts
  local installs
  installs="$(awk '/\\$/ { sub(/\\$/, ""); printf "%s", $0; next } 1' \
    "$INSTALL")"
  grep -qE -- '--needed .*cmake' <<<"$installs"
  grep -qE -- '--needed .*libvterm' <<<"$installs"
}
