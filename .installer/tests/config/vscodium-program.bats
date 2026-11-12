#!/usr/bin/env bats
# dev/vscodium program — the VSCodium Config, opt-in parity twin of the Neovim
# Config (ADR 0148). Static seam like nvim-program-*.bats: assert the COMMITTED
# program, its single-source home/ settings and the extension list — no install
# run. Config Apply places home/ (ADR 0134); install.sh installs the package +
# extensions only.

load ../lib/json-helpers
load ../lib/text-helpers

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
  FLEET="$REPO/.installer/hosts/fleet/profile.jsonc"
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
  json_satisfies "$(jsonc_strip "$CFG")" '.name == "vscodium" and .kind == "user"'
  json_satisfies "$(jsonc_strip "$CFG")" '.stow_opt_in == true'   # ADR 0148
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
  ! tree_has -i -E 'marketplace\.visualstudio|vscodium-marketplace' "$PROG"
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
  local lower_ids
  lower_ids="$(ext_ids | tr '[:upper:]' '[:lower:]')"
  # No extension id listed twice.
  [ -z "$(printf '%s\n' "$lower_ids" | sort | uniq -d)" ]
}

@test "the list carries VSCodeVim and the catppuccin theme + icons" {
  ext_ids | grep -qx 'vscodevim.vim'
  ext_ids | grep -qx 'catppuccin.catppuccin-vsc'
  ext_ids | grep -qx 'catppuccin.catppuccin-vsc-icons'
}

# ── single-source settings (ADR 0134) ────────────────────────────────────────

@test "settings.json and keybindings.json parse" {
  json_satisfies "$(jsonc_strip "$SETTINGS")" 'type == "object"'
  json_satisfies "$(jsonc_strip "$KEYS")" 'type == "array"'
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
  json_satisfies "$(setting '."vim.insertModeKeyBindings"')" \
    'any(.[]; .before == ["j","j"] and .after == ["<Esc>"])'
  [ "$(setting '."vim.useSystemClipboard"')" = 'true' ]
  [ "$(setting '."editor.lineNumbers"')" = '"relative"' ]
  json_satisfies "$(setting '."vim.handleKeys"')" \
    '.["<C-a>"] == false and .["<C-f>"] == false and .["<C-p>"] == false'
}

@test "a no-name ./stow-configs.sh sweep skips vscodium (ADR 0148)" {
  source "$REPO/.installer/lib/config/config-apply.sh"
  local root="$REPO/.installer/programs" opted_in selection
  opted_in="$(config_apply_stow_opted_in_programs "$root")"
  selection="$(config_apply_stow_selection \
    "$(config_apply_ships_home_list "$root")" '[]' '[]' "$opted_in")"
  json_satisfies "$opted_in" 'index("vscodium") != null'
  json_satisfies "$selection" 'index("vscodium") == null'
}

# ── languages on the system toolchain (ADR 0148) ─────────────────────────────

# registry_keys → the Language Registry's language keys (ADR 0141), read from
# nvim's languages.lua (lib/language-registry.awk) — no Lua runtime.
registry_keys() {
  awk -v part=keys -f "$BATS_TEST_DIRNAME/../lib/language-registry.awk" "$LANGS"
}

# registry_formatters → "<ft> <formatter>" per Registry filetype that formats.
registry_formatters() {
  awk -v part=formatters -f "$BATS_TEST_DIRNAME/../lib/language-registry.awk" \
    "$LANGS"
}

# coverage_keys → the Editor Coverage Map's language keys.
coverage_keys() {
  local key _rest
  # Each row's key (its first column), each once.
  while read -r key _rest; do
    printf '%s\n' "$key"
  done < <(data_rows "$COVERAGE") | sort -u
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
  local ids fields
  # Every extension a row names (the columns after its key; n/a names none).
  ids="$(while read -ra fields; do
      (( ${#fields[@]} > 1 )) || continue
      [[ "${fields[1]}" == n/a ]] && continue
      printf '%s\n' "${fields[@]:1}"
    done < <(data_rows "$COVERAGE"))"
  [ -n "$ids" ]
  local id
  while IFS= read -r id; do
    ext_ids | grep -qx "$id" || { echo "missing from list: $id"; false; }
  done < <(printf '%s\n' "$ids")
}

@test "an n/a Coverage Map row states a reason" {
  run bash -c "$(declare -f data_rows); data_rows '$COVERAGE' \
    | awk '\$2 == \"n/a\" && NF < 3'"
  [ -z "$output" ]
}

# Formatter name (Registry) → the VSCodium extension that formats with it.
# Independent of the settings: this is the ADR 0148 parity contract.
formatter_extension() {
  case "$1" in
  stylua) echo JohnnyMorganz.stylua ;;
  ruff_format) echo charliermarsh.ruff ;;
  biome) echo biomejs.biome ;;
  prettier) echo esbenp.prettier-vscode ;;
  gofmt) echo golang.go ;;
  rustfmt) echo rust-lang.rust-analyzer ;;
  zigfmt) echo ziglang.vscode-zig ;;
  clang_format) echo llvm-vs-code-extensions.vscode-clangd ;;
  nixfmt) echo jnoortheen.nix-ide ;;
  phpcbf) echo ValeryanM.vscode-phpsab ;;
  shfmt) echo mads-hartmann.bash-ide-vscode ;;
  taplo) echo tamasfe.even-better-toml ;;
  xmllint | kdlfmt) echo jkillian.custom-local-formatters ;;
  *) echo "UNMAPPED:$1" ;;
  esac
}

# nvim filetype → VSCodium language id (they differ only for shell).
vsc_lang() {
  case "$1" in
  sh | bash | zsh) echo shellscript ;;
  *) echo "$1" ;;
  esac
}

@test "each Registry formatter is the VSCodium default for its filetypes" {
  local filetype formatter want got
  run registry_formatters
  [ "${#lines[@]}" -ge 15 ]
  while read -r filetype formatter; do
    want="$(formatter_extension "$formatter")"
    # The filetype's default formatter, unquoted.
    got="$(setting ".\"[$(vsc_lang "$filetype")]\".\"editor.defaultFormatter\"" \
      | jq -r .)"
    [ "$got" = "$want" ] || { echo "$filetype: want $want got $got"; false; }
  done < <(registry_formatters)
}

@test "save behaves as nvim: format on save, no code actions, no autosave" {
  [ "$(setting '."editor.formatOnSave"')" = 'true' ]
  json_satisfies "$(setting '."editor.codeActionsOnSave" // {}')" 'length == 0'
  [ "$(setting '."files.autoSave" // "off"')" = '"off"' ]
}

# nvim's manual-only formatters (format_on_save = false, ADR 0151) skip save
# in VSCodium too.
@test "manual-only formatters skip format on save in both editors" {
  local filetype
  for filetype in shellscript kdl toml; do
    [ "$(setting ".\"[$filetype]\".\"editor.formatOnSave\"")" = false ] \
      || { echo "$filetype formats on save"; false; }
  done
  [ "$(grep -c "format_on_save = false" "$LANGS")" -eq 3 ]
}

# System path settings → the package providing that path. Each package must be
# declared by the Fleet Layer, be a dependency of one it declares (rust ←
# rust-src ← rust-analyzer, zig ← zls), or be installed by dev/nvim (phpactor,
# php-codesniffer).
@test "toolchain path settings point at Fleet Layer system binaries" {
  local key path package
  while read -r key path package; do
    # The setting's path (an array's first entry).
    got="$(setting ".$key" | jq -r 'if type == "array" then .[0] else . end')"
    [ "$got" = "$path" ] || { echo "$key: want $path got $got"; false; }
    # "@nvim:<package>": installed by dev/nvim.
    if [[ "$package" == @nvim:* ]]; then
      grep -q "needed ${package:6}" \
        "$REPO/.installer/programs/dev/nvim/install.sh"
    else
      grep -q "\"$package\"" "$FLEET" \
        || { echo "$package not in the Fleet Layer"; false; }
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
"phpactor.path" /usr/bin/phpactor @nvim:phpactor
"nix.formatterPath" /usr/bin/nixfmt nixfmt
"bashIde.shfmt.path" /usr/bin/shfmt shfmt
"phpsab.executablePathCBF" /usr/bin/phpcbf @nvim:php-codesniffer
"phpsab.executablePathCS" /usr/bin/phpcs @nvim:php-codesniffer
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
  local settings="$1"; shift
  local before keys bound
  keys='$keys | split("\n") | map(if . == "SPC" then " " else . end)'
  bound='[.[] | select(.before == $b)][0] | if . == null then "UNBOUND"'
  bound+=' elif .commands then (.commands[0] | if type == "object"'
  bound+=' then "\(.command) \(.args | tojson)" else . end)'
  bound+=' else (.after | join(" ")) end'
  # The key sequence as a JSON array (SPC is the space key).
  before="$(jq -cn --arg keys "$(printf '%s\n' "$@")" "$keys")"
  # What that sequence is bound to.
  setting ".\"$settings\"" | jq -r --argjson b "$before" "$bound"
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
  json_satisfies "$(setting ".\"$N\"")" \
    'any(.[]; .before == ["<leader>","g","g"]
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
  json_satisfies "$(jsonc_strip "$KEYS")" 'any(.[]; .key == "ctrl+/"
    and .command == "workbench.action.terminal.toggleTerminal")'
  json_satisfies "$(jsonc_strip "$KEYS")" 'any(.[]; .command == "toggleVim")'
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

@test "the Fleet Layer serves no VSCodium and no MS Marketplace patch (ADR 0148)" {
  # The program owns vscodium-bin (opt-in); vscodium-marketplace would point
  # --install-extension at the MS Marketplace instead of Open VSX.
  [ -z "$(grep '"vscodium-bin"' "$FLEET")" ]
  ! grep -q '"vscodium-marketplace"' "$FLEET"
}

@test "window nav <C-h/j/k/l> are native chords, normal mode + lists only" {
  # Native (keybindings.json), not VSCodeVim, so they also leave the explorer
  # and lists; like nvim, off in insert/visual and in the terminal (an input).
  local key command when="!inputFocus || editorTextFocus && vim.mode == 'Normal'"
  while read -r key command; do
    json_satisfies "$(jsonc_strip "$KEYS")" "any(.[]; .key == \"$key\"
      and .command == \"$command\" and .when == \"$when\")"
  done <<'EOF_'
ctrl+h workbench.action.navigateLeft
ctrl+j workbench.action.navigateDown
ctrl+k workbench.action.navigateUp
ctrl+l workbench.action.navigateRight
EOF_
  json_satisfies "$(setting ".\"$N\"")" 'all(.[]; .before != ["<C-h>"])'
}
