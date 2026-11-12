#!/usr/bin/env bats
# dev/emacs program — the Emacs Config, opt-in Doom Emacs parity twin of the
# Neovim Config (ADR 0160). Static seam like vscodium-program.bats: assert the
# COMMITTED program, its pin and its single-source home/ Doom config — no
# install run, no Emacs runtime. Config Apply places home/ (ADR 0134); the
# Post-Config Hook runs Doom's install against it.
# Helpers: emacs-program-helpers.bash.

load ../lib/text-helpers
load ../lib/json-helpers
load emacs-program-helpers

# ── program definition ───────────────────────────────────────────────────────

@test "dev/emacs config.jsonc declares an opt-in user-kind program" {
  [ -f "$CFG" ]
  json_satisfies "$(jsonc_strip "$CFG")" '.name == "emacs" and .kind == "user"'
  json_satisfies "$(jsonc_strip "$CFG")" '.stow_opt_in == true'   # ADR 0160
}

@test "Emacs is opt-in: not in User Core, listed by the operator" {
  ! grep -q '"emacs"' "$UCORE"
  json_satisfies "$(jsonc_strip "$OPERATOR")" '.programs | index("emacs") != null'
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
  run bash -c "$(declare -f data_rows); data_rows '$INSTALL' \
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
  run bash -c "$(declare -f data_rows); data_rows '$INSTALL' \
    | grep -E 'rm -r|rm -fr|rm -rf'"
  [ -z "$output" ]
}

# ── Post-Config Hook: Doom's install against the placed config ───────────────

@test "post-config.sh has the mandated shape" {
  [ -f "$HOOK" ]
  run bash -c "grep -vE '^[[:space:]]*(#|\$)' '$HOOK' | head -2"
  [[ "${lines[0]}" == "set -Eeuo pipefail" ]]
  [[ "${lines[1]}" == trap* ]]
  ! data_rows "$HOOK" | grep -qE 'systemctl|sudo'   # runs with no sudo
}

@test "post-config.sh runs Doom's install unattended, without an env file" {
  grep -qE 'bin/doom"? --force install --no-env' "$HOOK"
}

@test "post-config.sh skips (warns) when the Doom config was not placed" {
  grep -q 'init.el' "$HOOK"
  [ "$(grep -c 'print_status warning' "$HOOK")" -ge 2 ]
}

# ── the Doom config: modules and look (ADR 0160) ─────────────────────────────

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
  elisp "$DOOMDIR/config.el" \
    | grep -qF '(setq doom-theme (+parity--saved-palette))'
  elisp "$DOOMDIR/config.el" | grep -qF "'catppuccin)))"   # the fallback
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
  local root="$REPO/.installer/programs" opted_in selection
  opted_in="$(config_apply_stow_opted_in_programs "$root")"
  selection="$(config_apply_stow_selection \
    "$(config_apply_ships_home_list "$root")" '[]' '[]' "$opted_in")"
  json_satisfies "$opted_in" 'index("emacs") != null'
  json_satisfies "$selection" 'index("emacs") == null'
}

# ── languages on the system toolchain (ADR 0160) ─────────────────────────────

@test "LSP via eglot, flymake checking, format on save without LSP format" {
  module_enabled '(lsp +eglot)'
  module_enabled '(syntax +flymake)'
  module_enabled '(format +onsave)'
  # +lsp would hand formatting to the server, overriding conform's choice.
  ! elisp "$DOOMDIR/init.el" | grep -qE '\(format [^)]*\+lsp'
  ! elisp "$DOOMDIR/init.el" | grep -qE '(^|[[:space:]])debugger'
}

@test "Emacs Coverage Map keys == Language Registry keys (ADR 0160)" {
  local key _rest
  # The Coverage Map's keys (each row's first column), each once.
  diff <(registry_keys | sort) <(while read -r key _rest; do
      printf '%s\n' "$key"
    done < <(data_rows "$REPO/$COVERAGE_REL") | sort -u)
}

@test "every Coverage Map module is enabled and every package declared" {
  local token tokens
  local -a fields
  # Every token a row names: the columns after its key (n/a names none).
  tokens="$(while read -ra fields; do
      (( ${#fields[@]} > 1 )) || continue
      [[ "${fields[1]}" == n/a ]] && continue
      printf '%s\n' "${fields[@]:1}"
    done < <(data_rows "$REPO/$COVERAGE_REL"))"
  while read -r token; do
    case "$token" in
    # :lang/<module>: the module is enabled in init.el.
    :lang/*) elisp "$DOOMDIR/init.el" \
        | grep -qE "(^|[[:space:](])${token:6}([[:space:])]|$)" \
        || { echo "module off: $token"; false; } ;;
    # pkg:<package>: packages.el declares it.
    pkg:*) elisp "$DOOMDIR/packages.el" \
        | grep -qF "(package! ${token:4} " \
        || { echo "package missing: $token"; false; } ;;
    builtin:*) ;;
    *) echo "unknown token: $token"; false ;;
    esac
  done < <(printf '%s\n' "$tokens")
}

@test "an n/a Coverage Map row states a reason" {
  local -a fields
  while read -ra fields; do
    # An n/a row needs a reason after it.
    [[ "${fields[1]:-}" == n/a ]] || continue
    (( ${#fields[@]} >= 3 )) || { echo "no reason: ${fields[0]}"; false; }
  done < <(data_rows "$REPO/$COVERAGE_REL")
}

# Each Registry server → the system binary eglot must launch and the Fleet
# Layer package providing it. phpactor rides dev/nvim's install.
@test "eglot launches every Registry server from the system toolchain" {
  local binary package
  while read -r binary package; do
    elisp "$DOOMDIR/config.el" | grep -qF "\"$binary\"" \
      || { echo "no eglot client for $binary"; false; }
    # "@nvim:<package>": installed by dev/nvim.
    if [[ "$package" == @nvim:* ]]; then
      grep -q "needed ${package:6}" \
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
typescript-tsx-mode biome
js-jsx-mode biome
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
    # The format-on-save-disabled modes list names the mode.
    elisp "$DOOMDIR/config.el" \
      | lines_between '\+format-on-save-disabled-modes' '\)\)' \
      | grep -qw "$mode" \
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

@test ".tsx/.jsx get modes eglot names typescriptreact/javascriptreact" {
  # Doom maps them only with +tree-sitter, and Arch packages no TypeScript
  # grammar: a typescript-mode child carries nvim's typescriptreact.
  elisp "$DOOMDIR/config.el" \
    | grep -qF '(define-derived-mode typescript-tsx-mode typescript-mode'
  elisp "$DOOMDIR/config.el" \
    | grep -qF '("\\.tsx\\'"'"'" . typescript-tsx-mode)'
  elisp "$DOOMDIR/config.el" | grep -qF '("\\.jsx\\'"'"'" . js-jsx-mode)'
  elisp "$DOOMDIR/config.el" \
    | grep -qF '(typescript-tsx-mode :language-id "typescriptreact")'
  elisp "$DOOMDIR/config.el" \
    | grep -qF '(js-jsx-mode :language-id "javascriptreact")'
}

@test "nerd-icons draws from the seeded FiraCode Nerd Font, no download" {
  elisp "$DOOMDIR/config.el" \
    | grep -qF '(setq nerd-icons-font-family "FiraCode Nerd Font")'
}

@test "the snippets dir Doom's snippets module reads ships (no yas warning)" {
  module_enabled 'snippets'
  [ -d "$DOOMDIR/snippets" ]
}

# VM: Doom's evil caches the cursor color at depth -100 of the theme hook,
# before theme face customizations apply, so the cursor stayed rosewater.
@test "evil re-reads the cursor color after the sapphire overlay" {
  elisp "$DOOMDIR/config.el" | grep -qF '+evil-update-cursor-color-h'
}

# Audit Run: the runner passes FA_DIR with a trailing slash; Emacs' `load'
# reads "dir//file" as "/file", so the judge silently judged nothing.
@test "audit.sh drops FA_DIR's trailing slash and fails an empty judge" {
  grep -qF 'fixtures="$(readlink -m "$FA_DIR")/audit-fixtures"' "$PROG/audit.sh"
  grep -qF 'feature_audit_fail emacs-binds' "$PROG/audit.sh"
}
