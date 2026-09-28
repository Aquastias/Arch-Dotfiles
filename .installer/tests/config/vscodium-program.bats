#!/usr/bin/env bats
# dev/vscodium program — the VSCodium Config, opt-in parity twin of the Neovim
# Config (ADR 0148). Static seam like nvim-program.bats: assert the COMMITTED
# program, its single-source home/ settings and the extension list — no install
# run. Config Apply places home/ (ADR 0134); install.sh installs the package +
# extensions only.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."   # .installer/tests/config → repo root
  PROG="$REPO/.installer/programs/dev/vscodium"
  CFG="$PROG/config.jsonc"
  INSTALL="$PROG/install.sh"
  EXTS="$PROG/extensions.txt"
  USERDIR="$PROG/home/.config/VSCodium/User"
  SETTINGS="$USERDIR/settings.json"
  KEYS="$USERDIR/keybindings.json"
  UCORE="$REPO/.installer/users/core/profile.jsonc"
  HOSTCORE="$REPO/.installer/hosts/core/profile.jsonc"
  COVERAGE="$PROG/coverage.txt"
  LANGS="$REPO/.installer/programs/dev/nvim/home/.config/nvim/lua/config"
  LANGS="$LANGS/languages.lua"             # the Language Registry
  # shellcheck source=../../lib/jsonc.sh
  source "$REPO/.installer/lib/jsonc.sh"
}

# setting <jq-path> → the settings.json value (JSON-encoded).
setting() { jsonc_strip "$SETTINGS" | jq -c "$1"; }

# data_rows FILE → the rows of a data file, `#` comments and blanks dropped.
data_rows() { grep -vE '^[[:space:]]*(#|$)' "$1"; }

# ext_ids → the extension list, comments and blanks dropped.
ext_ids() { data_rows "$EXTS"; }

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
  # No code line touches home/, the VSCodium config dir, /etc/skel or /root.
  run bash -c "grep -vE '^[[:space:]]*#' '$INSTALL' \
    | grep -E 'home/|\.config/VSCodium|etc/skel|/root'"
  [ -z "$output" ]
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
  [ "$(setting '."terminal.integrated.fontSize"')" = '12' ]
  [ "$(setting '."terminal.integrated.fontLigatures.enabled"')" = 'true' ]
}

@test "layout: sidebar right, no startup editor, sticky scroll" {
  [ "$(setting '."workbench.sideBar.location"')" = '"right"' ]
  [ "$(setting '."workbench.startupEditor"')" = '"none"' ]
  [ "$(setting '."editor.stickyScroll.enabled"')" = 'true' ]
  [ "$(setting '."workbench.secondarySideBar.defaultVisibility"')" \
    = '"hidden"' ]
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

# ── languages on the system toolchain (ADR 0148) ─────────────────────────────

# registry_keys → the Language Registry's language keys (ADR 0141), read from
# nvim's languages.lua with awk — no Lua runtime.
registry_keys() {
  awk '/^local registry = \{/ { on = 1; next }
       on && /^}/ { exit }
       on && match($0, /^  [a-z_]+ = /) {
         k = substr($0, 3); sub(/ = .*/, "", k); print k }' \
    "$LANGS"
}

# registry_formatters → "<ft> <formatter>" per Registry filetype that formats.
registry_formatters() {
  awk '/^local registry = \{/ { on = 1; next }
       on && /^}/ { exit }
       on && /^  [a-z_]+ = / { ft = ""; fmt = "" }
       on && /ft = \{/ { s = $0; sub(/.*ft = \{/, "", s); sub(/\}.*/, "", s)
                         ft = s }
       on && /formatter = \{/ { s = $0; sub(/.*formatter = \{/, "", s)
                                sub(/\}.*/, "", s); fmt = s }
       on && ft != "" && fmt != "" {
         gsub(/[" ]/, "", ft); gsub(/[" ]/, "", fmt)
         n = split(ft, fts, ","); split(fmt, f, ",")
         for (i = 1; i <= n; i++) if (fts[i] != "") print fts[i], f[1]
         ft = ""; fmt = "" }' \
    "$LANGS"
}

# coverage_keys → the Editor Coverage Map's language keys.
coverage_keys() {
  data_rows "$COVERAGE" | awk '{print $1}' | sort -u
}

@test "the Registry parse sees the languages nvim wires (sanity)" {
  run registry_keys
  [[ " ${lines[*]} " == *" lua "* ]]
  [[ " ${lines[*]} " == *" typescript "* ]]
  [[ " ${lines[*]} " == *" typst "* ]]
  [ "${#lines[@]}" -ge 20 ]
}

@test "Editor Coverage Map keys == Language Registry keys (ADR 0148)" {
  diff <(registry_keys | sort) <(coverage_keys | sort)
}

@test "every Coverage Map extension is in the extension list" {
  local ids
  ids="$(data_rows "$COVERAGE" \
    | awk '$2 != "n/a" { for (i = 2; i <= NF; i++) print $i }')"
  [ -n "$ids" ]
  local id
  while IFS= read -r id; do
    ext_ids | grep -qx "$id" || { echo "missing from list: $id"; false; }
  done <<<"$ids"
}

@test "an n/a Coverage Map row states a reason" {
  run bash -c "$(declare -f data_rows); data_rows '$COVERAGE' \
    | awk '\$2 == \"n/a\" && NF < 3'"
  [ -z "$output" ]
}

# Formatter name (Registry) → the VSCodium extension that formats with it.
# Independent of the settings: this is the ADR 0148 parity contract.
fmt_ext() {
  case "$1" in
  stylua) echo JohnnyMorganz.stylua ;;
  ruff_format) echo charliermarsh.ruff ;;
  biome) echo biomejs.biome ;;
  prettier) echo esbenp.prettier-vscode ;;
  gofmt) echo golang.go ;;
  rustfmt) echo rust-lang.rust-analyzer ;;
  zigfmt) echo ziglang.vscode-zig ;;
  *) echo "UNMAPPED:$1" ;;
  esac
}

@test "each Registry formatter is the VSCodium default for its filetypes" {
  local ft fmt want got
  run registry_formatters
  [ "${#lines[@]}" -ge 15 ]
  while read -r ft fmt; do
    want="$(fmt_ext "$fmt")"
    got="$(setting ".\"[$ft]\".\"editor.defaultFormatter\"" | jq -r .)"
    [ "$got" = "$want" ] || { echo "$ft: want $want got $got"; false; }
  done < <(registry_formatters)
}

@test "save behaves as nvim: format on save, no code actions, no autosave" {
  [ "$(setting '."editor.formatOnSave"')" = 'true' ]
  setting '."editor.codeActionsOnSave" // {}' | jq -e 'length == 0'
  [ "$(setting '."files.autoSave" // "off"')" = '"off"' ]
}

# System path settings → the package providing that path. Each package must be
# declared by Host Core, be a dependency of one it declares (rust ← rust-src ←
# rust-analyzer, zig ← zls), or be installed by dev/nvim (phpactor).
@test "toolchain path settings point at Host Core system binaries" {
  local key path pkg
  while read -r key path pkg; do
    got="$(setting ".$key" | jq -r 'if type == "array" then .[0] else . end')"
    [ "$got" = "$path" ] || { echo "$key: want $path got $got"; false; }
    if [ "$pkg" = "@nvim" ]; then
      grep -q 'needed phpactor' "$REPO/.installer/programs/dev/nvim/install.sh"
    else
      grep -q "\"$pkg\"" "$HOSTCORE" \
        || { echo "$pkg not in Host Core"; false; }
    fi
  done <<'EOF_'
"rust-analyzer.server.path" /usr/bin/rust-analyzer rust-analyzer
"go.alternateTools".gopls /usr/bin/gopls gopls
"go.alternateTools".dlv /usr/bin/dlv delve
"ruff.path" /usr/bin/ruff ruff
"biome.lsp.bin" /usr/bin/biome biome
"prettier.prettierPath" /usr/lib/node_modules/prettier prettier
"stylua.styluaPath" /usr/bin/stylua stylua
"Lua.misc.executablePath" /usr/bin/lua-language-server lua-language-server
"clangd.path" /usr/bin/clangd clang
"zig.path" /usr/bin/zig zls
"zig.zls.path" /usr/bin/zls zls
"nix.serverPath" /usr/bin/nixd nixd
"phpactor.path" /usr/bin/phpactor @nvim
"svelte.language-server.ls-path" /usr/bin/svelteserver svelte-language-server
"vue.server.path" /usr/lib/node_modules/@vue/language-server vue-language-server
EOF_
}

@test "managed tool downloads are off (Go tools, zig/zls)" {
  [ "$(setting '."go.toolsManagement.autoUpdate"')" = 'false' ]
  [ "$(setting '."go.toolsManagement.checkForUpdates"')" = '"off"' ]
  [ "$(setting '."zig.zls.enabled"')" = '"on"' ]
}

# ── key parity with the Neovim Config (ADR 0148) ─────────────────────────────

# bind <setting> <keys…> → the first command bound to that key sequence (or
# its `after` keys, space-joined). `SPC` stands for the space key.
bind() {
  local s="$1"; shift
  local before; before="$(printf '%s\n' "$@" | sed 's/^SPC$/ /' | jq -R . \
    | jq -sc .)"
  setting ".\"$s\"" | jq -r --argjson b "$before" '
    [ .[] | select(.before == $b) ][0]
    | if . == null then "UNBOUND"
      elif .commands then (.commands[0] | if type == "object"
        then "\(.command) \(.args | tojson)" else . end)
      else (.after | join(" ")) end'
}
N=vim.normalModeKeyBindingsNonRecursive
V=vim.visualModeKeyBindingsNonRecursive

@test "motions: sneak on s/S, easymotion off, surround on" {
  [ "$(setting '."vim.sneak"')" = 'true' ]
  [ "$(setting '."vim.easymotion"')" = 'false' ]
  [ "$(setting '."vim.surround"')" = 'true' ]
}

@test "surround rides nvim's gs* keys (mini.surround)" {
  [ "$(bind "$N" g s a)" = '<plugys>' ]
  [ "$(bind "$N" g s d)" = '<plugds>' ]
  [ "$(bind "$N" g s r)" = '<plugcs>' ]
}

@test "find/search leader keys match nvim's snacks + grug-far maps" {
  [ "$(bind "$N" '<leader>' SPC)" = 'workbench.action.quickOpen' ]
  [ "$(bind "$N" '<leader>' f f)" = 'workbench.action.quickOpen' ]
  [ "$(bind "$N" '<leader>' f g)" = 'workbench.action.findInFiles' ]
  [ "$(bind "$N" '<leader>' f b)" = 'workbench.action.showAllEditors' ]
  [ "$(bind "$N" '<leader>' f r)" = 'workbench.action.openRecent' ]
  [ "$(bind "$N" '<leader>' s s)" = 'workbench.action.gotoSymbol' ]
  [ "$(bind "$N" '<leader>' s S)" = 'workbench.action.showAllSymbols' ]
  [ "$(bind "$N" '<leader>' s c)" = 'workbench.action.showCommands' ]
  [ "$(bind "$N" '<leader>' s k)" = 'workbench.action.openGlobalKeybindings' ]
  [ "$(bind "$N" '<leader>' s r)" = 'workbench.action.replaceInFiles' ]
}

@test "LSP keys match nvim's gr*/K + <leader>co" {
  [ "$(bind "$N" g r n)" = 'editor.action.rename' ]
  [ "$(bind "$N" g r a)" = 'editor.action.quickFix' ]
  [ "$(bind "$N" g r r)" = 'editor.action.goToReferences' ]
  [ "$(bind "$N" g r i)" = 'editor.action.goToImplementation' ]
  [ "$(bind "$N" g r d)" = 'editor.action.revealDefinition' ]
  [ "$(bind "$N" K)" = 'editor.action.showHover' ]
  [ "$(bind "$N" '<leader>' c o)" = 'editor.action.organizeImports' ]
}

@test "jumps + trouble keys: ]d/[d, ]h/[h, <leader>xx/xt" {
  [ "$(bind "$N" ']' d)" = 'editor.action.marker.next' ]
  [ "$(bind "$N" '[' d)" = 'editor.action.marker.prev' ]
  [ "$(bind "$N" ']' h)" = 'workbench.action.editor.nextChange' ]
  [ "$(bind "$N" '[' h)" = 'workbench.action.editor.previousChange' ]
  [ "$(bind "$N" '<leader>' x x)" = 'workbench.actions.view.problems' ]
  [ "$(bind "$N" '<leader>' x t)" = 'todo-tree-view.focus' ]
}

@test "git keys: lazygit in terminal, diff, file/repo history, blame" {
  [ "$(bind "$N" '<leader>' g g)" = 'workbench.action.terminal.new' ]
  setting ".\"$N\"" | jq -e 'any(.[]; .before == ["<leader>","g","g"]
    and any(.commands[] | objects; .args.text == "lazygit\n"))'
  [ "$(bind "$N" '<leader>' g d)" = 'git.openChange' ]
  [ "$(bind "$N" '<leader>' g h)" = 'timeline.focus' ]
  [ "$(bind "$N" '<leader>' g H)" = 'git-graph.view' ]
  [ "$(bind "$N" '<leader>' g t)" = 'git.blame.toggleEditorDecoration' ]
}

@test "explorer, buffers, windows, basics match nvim" {
  [ "$(bind "$N" -)" = 'workbench.files.action.showActiveFileInExplorer' ]
  [ "$(bind "$N" '<leader>' e)" = 'workbench.view.explorer' ]
  [ "$(bind "$N" '<Tab>')" = 'workbench.action.nextEditor' ]
  [ "$(bind "$N" '<S-Tab>')" = 'workbench.action.previousEditor' ]
  [ "$(bind "$N" '<leader>' b d)" = 'workbench.action.closeActiveEditor' ]
  [ "$(bind "$N" '<leader>' w)" = 'workbench.action.files.save' ]
  [ "$(bind "$N" '<leader>' q)" = 'workbench.action.closeActiveEditor' ]
  [ "$(bind "$N" '<Esc>')" = ':nohl' ]
  [ "$(bind "$N" '<leader>' y p)" = 'copyFilePath' ]
}

@test "UI, REST and refactor keys match nvim" {
  [ "$(bind "$N" '<leader>' u C)" = 'workbench.action.selectTheme' ]
  [ "$(bind "$N" '<leader>' R s)" = 'rest-client.request' ]
  [ "$(bind "$N" '<leader>' R c)" = 'rest-client.copy-request-as-curl' ]
  [ "$(bind "$V" '<leader>' r e)" \
    = 'editor.action.codeAction {"kind":"refactor.extract"}' ]
  [ "$(bind "$V" '<leader>' r v)" \
    = 'editor.action.codeAction {"kind":"refactor.extract"}' ]
  [ "$(bind "$V" '<leader>' r f)" \
    = 'editor.action.codeAction {"kind":"refactor.move"}' ]
  [ "$(bind "$N" '<leader>' r i)" \
    = 'editor.action.codeAction {"kind":"refactor.inline"}' ]
}

@test "visual keys: J/K move, </> keep selection, <leader>p keeps register" {
  [ "$(bind "$V" J)" = 'editor.action.moveLinesDownAction' ]
  [ "$(bind "$V" K)" = 'editor.action.moveLinesUpAction' ]
  [ "$(bind "$V" '>')" = 'editor.action.indentLines' ]
  [ "$(bind "$V" '<')" = 'editor.action.outdentLines' ]
  [ "$(bind "$V" '<leader>' p)" = '" _ d P' ]
  [ "$(bind "$N" '<C-space>')" = 'editor.action.smartSelect.expand' ]
  [ "$(bind "$V" '<BS>')" = 'editor.action.smartSelect.shrink' ]
}

@test "native chords: <C-/> toggles the terminal, ctrl+alt+v toggles vim" {
  jsonc_strip "$KEYS" | jq -e 'any(.[]; .key == "ctrl+/"
    and .command == "workbench.action.terminal.toggleTerminal")'
  jsonc_strip "$KEYS" | jq -e 'any(.[]; .command == "toggleVim")'
}

@test "the five nvim palettes are installed for <leader>uC" {
  ext_ids | grep -qx 'catppuccin.catppuccin-vsc'
  ext_ids | grep -qx 'mvllow.rose-pine'
  ext_ids | grep -qx 'enkia.tokyo-night'
  ext_ids | grep -qx 'jdinhlife.gruvbox'
  ext_ids | grep -qx 'arcticicestudio.nord-visual-studio-code'
}

@test "kept extras: todo-tree, git-graph, spell checker (ADR 0148)" {
  ext_ids | grep -qx 'Gruntfuggly.todo-tree'
  ext_ids | grep -qx 'mhutchie.git-graph'
  ext_ids | grep -qx 'streetsidesoftware.code-spell-checker'
}

# ── debugging parity with nvim-dap (ADR 0140/0148) ───────────────────────────

@test "debug keys match nvim's <leader>d* maps" {
  [ "$(bind "$N" '<leader>' d b)" = 'editor.debug.action.toggleBreakpoint' ]
  [ "$(bind "$N" '<leader>' d B)" \
    = 'editor.debug.action.conditionalBreakpoint' ]
  [ "$(bind "$N" '<leader>' d c)" = 'workbench.action.debug.continue' ]
  [ "$(bind "$N" '<leader>' d l)" = 'workbench.action.debug.start' ]
  [ "$(bind "$N" '<leader>' d i)" = 'workbench.action.debug.stepInto' ]
  [ "$(bind "$N" '<leader>' d o)" = 'workbench.action.debug.stepOver' ]
  [ "$(bind "$N" '<leader>' d O)" = 'workbench.action.debug.stepOut' ]
  [ "$(bind "$N" '<leader>' d r)" = 'workbench.debug.action.toggleRepl' ]
  [ "$(bind "$N" '<leader>' d t)" = 'workbench.action.debug.stop' ]
  [ "$(bind "$N" '<leader>' d u)" = 'workbench.view.debug' ]
}

@test "every nvim dap target has a debugger (Registry dap column)" {
  # python → debugpy, go → golang.go (system dlv), rust/c/cpp → codelldb;
  # js/ts use VSCodium's built-in js-debug.
  ext_ids | grep -qx 'ms-python.python'
  ext_ids | grep -qx 'ms-python.debugpy'
  ext_ids | grep -qx 'vadimcn.vscode-lldb'
  grep -E '^python[[:space:]]' "$COVERAGE" | grep -q 'ms-python.debugpy'
  grep -E '^rust[[:space:]]' "$COVERAGE" | grep -q 'vadimcn.vscode-lldb'
  grep -E '^c[[:space:]]' "$COVERAGE" | grep -q 'vadimcn.vscode-lldb'
  grep -E '^cpp[[:space:]]' "$COVERAGE" | grep -q 'vadimcn.vscode-lldb'
}

@test "the Python extension adds no second language server (basedpyright)" {
  [ "$(setting '."python.languageServer"')" = '"None"' ]
}

@test "Host Core serves no VSCodium and no MS Marketplace patch (ADR 0148)" {
  # The program owns vscodium-bin (opt-in); vscodium-marketplace would point
  # --install-extension at the MS Marketplace instead of Open VSX.
  ! grep -q '"vscodium-bin"' "$HOSTCORE"
  ! grep -q '"vscodium-marketplace"' "$HOSTCORE"
}

@test "window nav <C-h/j/k/l> are native chords, normal mode + lists only" {
  # Native (keybindings.json), not VSCodeVim, so they also leave the explorer
  # and lists; like nvim, off in insert/visual and in the terminal (an input).
  local key cmd w="!inputFocus || editorTextFocus && vim.mode == 'Normal'"
  while read -r key cmd; do
    jsonc_strip "$KEYS" | jq -e --arg k "$key" --arg c "$cmd" --arg w "$w" \
      'any(.[]; .key == $k and .command == $c and .when == $w)'
  done <<'EOF_'
ctrl+h workbench.action.navigateLeft
ctrl+j workbench.action.navigateDown
ctrl+k workbench.action.navigateUp
ctrl+l workbench.action.navigateRight
EOF_
  setting ".\"$N\"" | jq -e 'all(.[]; .before != ["<C-h>"])'
}
