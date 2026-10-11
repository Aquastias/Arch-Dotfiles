#!/usr/bin/env bats
# Tests: IDE plugins (split from nvim-program.bats;
# shared setup in nvim-program-helpers.bash)

load nvim-program-helpers


# ── IDE expansion: trouble + navigation (ticket 05) ──────────────────────────

@test "trouble is declared, lazy, mapped under <leader>x" {
  local plugin_file="$NVIM/lua/plugins/trouble.lua"
  [ -f "$plugin_file" ]
  grep -q 'folke/trouble.nvim' "$plugin_file"
  grep -q 'cmd = "Trouble"' "$plugin_file"
  grep -q '"<leader>xx"' "$plugin_file"
  grep -q 'todo toggle' "$plugin_file"
}

@test "bracket navigation for diagnostics, hunks and todos" {
  grep -q '"]d"' "$NVIM/lua/config/keymaps.lua"
  grep -q 'diagnostic.jump' "$NVIM/lua/config/keymaps.lua"
  grep -q '"]h"' "$NVIM/lua/plugins/gitsigns.lua"
  grep -q '"]t"' "$NVIM/lua/plugins/todo-comments.lua"
}


# ── IDE expansion: API testing (ticket 06; rest.nvim, ADR 0150) ──────────────

@test "rest.nvim is declared, lazy on http ft, mapped under <leader>R" {
  local plugin_file="$NVIM/lua/plugins/rest.lua"
  [ -f "$plugin_file" ]
  grep -q 'rest-nvim/rest.nvim' "$plugin_file"
  grep -qE '^\s*ft = "http"' "$plugin_file"
  grep -q '"<leader>Rs"' "$plugin_file"
  grep -q 'filetype.add' "$plugin_file"
  [ ! -f "$NVIM/lua/plugins/kulala.lua" ]
}

@test "lazy rocks use system luarocks, never hererocks (ADR 0150)" {
  grep -q 'rocks = { enabled = true, hererocks = false }' \
    "$NVIM/lua/config/lazy.lua"
  grep -q 'luarocks lua51 jq' "$INSTALL"
}

@test "rest.nvim pretty-prints JSON responses with jq" {
  grep -q 'json = "jq"' "$NVIM/lua/plugins/rest.lua"
}


# ── IDE expansion: grug-far find & replace (ticket 07) ───────────────────────

@test "grug-far is declared, lazy, mapped under <leader>s" {
  local plugin_file="$NVIM/lua/plugins/grug-far.lua"
  [ -f "$plugin_file" ]
  grep -q 'MagicDuck/grug-far.nvim' "$plugin_file"
  grep -q 'cmd = "GrugFar"' "$plugin_file"
  grep -q '"<leader>sr"' "$plugin_file"
}


# ── IDE expansion: refactoring (ticket 08) ───────────────────────────────────

@test "refactoring is declared, lazy, mapped under <leader>r" {
  local plugin_file="$NVIM/lua/plugins/refactoring.lua"
  [ -f "$plugin_file" ]
  grep -q 'ThePrimeagen/refactoring.nvim' "$plugin_file"
  grep -q 'extract_func' "$plugin_file"
  grep -q 'inline_var' "$plugin_file"
  grep -q '"<leader>re"' "$plugin_file"
}


# ── IDE expansion: ergonomics plugins (ticket 09) ────────────────────────────

@test "ergonomics plugins: surround, autotag, ts-context, flash, colors" {
  local plugins_directory="$NVIM/lua/plugins"
  grep -rq 'echasnovski/mini.surround' "$plugins_directory"
  grep -rq 'windwp/nvim-ts-autotag' "$plugins_directory"
  grep -rq 'nvim-treesitter/nvim-treesitter-context' "$plugins_directory"
  grep -rq 'folke/flash.nvim' "$plugins_directory"
  grep -rq 'brenoprata10/nvim-highlight-colors' "$plugins_directory"
}

@test "surround uses the gs prefix so flash keeps s" {
  grep -q 'add = "gsa"' "$NVIM/lua/plugins/mini.lua"
  grep -qE '^\s*"s",' "$NVIM/lua/plugins/flash.lua"
  grep -q 'flash").jump' "$NVIM/lua/plugins/flash.lua"
}


# ── IDE expansion: LSP UX (ticket 10) ────────────────────────────────────────

@test "inlay hints default on with a <leader>uh toggle" {
  grep -q 'inlay_hint.enable(true' "$NVIM/lua/plugins/lsp.lua"
  grep -q '"<leader>uh"' "$NVIM/lua/config/keymaps.lua"
  grep -q 'inlay_hint' "$NVIM/lua/config/keymaps.lua"
}

@test "signature help is enabled in blink" {
  grep -q 'signature = { enabled = true' "$NVIM/lua/plugins/blink.lua"
}

@test "symbols, workspace symbols, palette and organize-imports mapped" {
  grep -q 'lsp_symbols' "$NVIM/lua/plugins/snacks.lua"
  grep -q 'lsp_workspace_symbols' "$NVIM/lua/plugins/snacks.lua"
  grep -q '"<leader>sc"' "$NVIM/lua/plugins/snacks.lua"
  grep -q 'organizeImports' "$NVIM/lua/plugins/lsp.lua"
}


# ── IDE expansion: native editing power (ticket 11) ──────────────────────────

@test "native multi-cursor keymaps, no multi-cursor plugin" {
  grep -q 'cgn' "$NVIM/lua/config/keymaps.lua"
  grep -q '"cn"' "$NVIM/lua/config/keymaps.lua"
  ! grep -rqiE 'multicursor|visual-multi' "$NVIM/lua"
}

@test "mini.ai wires treesitter function/class textobjects" {
  local plugin_file="$NVIM/lua/plugins/mini.lua"
  grep -q 'gen_spec.treesitter' "$plugin_file"
  grep -q '@function.outer' "$plugin_file"
  grep -q 'nvim-treesitter-textobjects' "$plugin_file"
}

@test "incremental selection + context-aware comments present" {
  [ -f "$NVIM/lua/config/incremental.lua" ]
  grep -q '"<C-space>"' "$NVIM/lua/config/keymaps.lua"
  grep -rq 'JoosepAlviste/nvim-ts-context-commentstring' "$NVIM/lua/plugins"
}


# ── IDE expansion: UI ergonomics + keybind conventions (ticket 12) ───────────

@test "snacks indent guides on; terminal + bufdelete mapped" {
  local plugin_file="$NVIM/lua/plugins/snacks.lua"
  grep -q 'indent = { enabled = true }' "$plugin_file"
  grep -q 'Snacks.terminal' "$plugin_file"
  grep -q '"<leader>bd"' "$plugin_file"
}

@test "which-key registers the leader group prefixes" {
  local plugin_file="$NVIM/lua/plugins/which-key.lua"
  grep -q 'group = "debug"' "$plugin_file"
  grep -q 'group = "git"' "$plugin_file"
  grep -q 'group = "refactor"' "$plugin_file"
}

@test "undotree moved off <leader>u so u is the ui group" {
  grep -q '"<leader>U"' "$NVIM/lua/plugins/undotree.lua"
  ! grep -q '"<leader>u"' "$NVIM/lua/plugins/undotree.lua"
}


# ── IDE expansion: folding tune (ticket 13) ──────────────────────────────────

@test "ufo tuned: lsp->treesitter->indent, foldtext, peek, foldcolumn" {
  local plugin_file="$NVIM/lua/plugins/ufo.lua"
  grep -q '"lsp"' "$plugin_file"
  grep -q '"treesitter"' "$plugin_file"
  grep -q '"indent"' "$plugin_file"
  grep -q 'fold_virt_text_handler' "$plugin_file"
  grep -q 'peekFoldedLinesUnderCursor' "$plugin_file"
  grep -q 'foldcolumn = "1"' "$plugin_file"
  grep -q '"zK"' "$plugin_file"
  grep -q '"zr"' "$plugin_file"
}

@test "lsp advertises foldingRange for ufo's LSP provider" {
  grep -q 'foldingRange' "$NVIM/lua/plugins/lsp.lua"
}

@test "the program installs neovim itself before the plugin restore" {
  # Regression (Audit Run 20261003): pure variants (packages.inherit false)
  # had no nvim, so the restore died "nvim: command not found".
  local ins rst
  local packages='--needed neovim git tree-sitter-cli'
  ins="$(NEEDLE="$packages" awk 'index($0, ENVIRON["NEEDLE"]) { print NR }' "$INSTALL")"
  rst="$(awk 'index($0, "nvim \"${_restore") { print NR; exit }' "$INSTALL")"
  [ -n "$ins" ] && [ -n "$rst" ] && (( ins < rst ))
}

@test "audit fixture: visual binds paste a known register, not the clipboard" {
  # kde-pure 20261004: <leader>p ("_dP) flaked on the session clipboard
  local key_fixture="$BATS_TEST_DIRNAME/../../programs/dev/nvim/audit-fixtures/key.lua"
  grep -q 'vim.o.clipboard = ""' "$key_fixture"
  grep -q "setreg('\"', \"fa-audit-paste\")" "$key_fixture"
}
