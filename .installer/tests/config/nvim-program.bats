#!/usr/bin/env bats
# dev/nvim program + hand-rolled Neovim Config (ADR 0135). Static seam like
# kitty-program.bats / pi-agent.bats: assert the COMMITTED program definition,
# single-source home/ config, and the static Catppuccin Mocha Sapphire default
# — no install run. Config is decoupled from install (ADR 0134): the Runner's
# Config Apply pass copies home/, so install.sh installs packages only.
# Grows per ticket: the LSP/formatter toolchain packages (02/03); the Neovim
# Theme Template live-follow wiring is asserted in noctalia-stow.bats (07).

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."        # .installer/tests/config → repo root
  PROG="$REPO/.installer/programs/dev/nvim"
  CFG="$PROG/config.jsonc"
  INSTALL="$PROG/install.sh"
  HOMESEED="$PROG/home"
  NVIM="$HOMESEED/.config/nvim"             # single source (ADR 0134)
  UCORE="$REPO/.installer/users/core/profile.jsonc"
}

# ── program definition ───────────────────────────────────────────────────────

@test "dev/nvim config.jsonc declares the user-kind nvim program" {
  [ -f "$CFG" ]
  grep -q '"name": "nvim"' "$CFG"
  grep -q '"kind": "user"' "$CFG"
}

@test "install.sh has the mandated shape and starts no service" {
  [ -f "$INSTALL" ]
  # set -Eeuo pipefail + trap are the first two non-comment lines (PROGRAM_SPEC)
  run bash -c "grep -vE '^[[:space:]]*(#|\$)' '$INSTALL' | head -2"
  [[ "${lines[0]}" == "set -Eeuo pipefail" ]]
  [[ "${lines[1]}" == trap* ]]
  grep -q 'print_status success' "$INSTALL"
  ! grep -qE 'systemctl (start|restart)' "$INSTALL"
}

@test "install.sh does NOT seed home/ config — the pass applies it (ADR 0134)" {
  ! grep -q 'cp -a "${SELF}/home/." "${HOME}/"' "$INSTALL"
  ! grep -q 'cp -a "${SELF}/home/." /etc/skel/' "$INSTALL"
  ! grep -q 'cp -a "${SELF}/home/." /root/' "$INSTALL"
}

# ── single-source config (ADR 0134) ──────────────────────────────────────────

@test "home/ is the single source of the served config" {
  [ -d "$NVIM" ]
  [ -f "$NVIM/init.lua" ]
  [ -f "$NVIM/lua/config/lazy.lua" ]
  [ -f "$NVIM/lua/config/options.lua" ]
}

@test "config is hand-rolled on lazy.nvim, not the LazyVim distro (ADR 0135)" {
  grep -rq 'folke/lazy.nvim' "$NVIM/lua/config/lazy.lua"
  ! grep -rq 'LazyVim/LazyVim' "$NVIM"
  ! grep -rq 'import = "lazyvim' "$NVIM"
}

# ── static default look (ADR 0136) ───────────────────────────────────────────

@test "default look is Catppuccin Mocha with a sapphire accent (ADR 0136)" {
  # palette switching + the follow_noctalia live path arrive in tickets 06/07
  grep -rq 'catppuccin' "$NVIM/lua/plugins"
  grep -rq 'mocha' "$NVIM/lua/plugins"
  grep -rq '#74c7ec' "$NVIM/lua/plugins"    # Catppuccin sapphire accent
}

@test "follow_noctalia defaults to false (static out of the box, ADR 0136)" {
  grep -rqE 'follow_noctalia[[:space:]]*=[[:space:]]*false' "$NVIM/lua"
}

@test "unused language providers are disabled so checkhealth stays quiet" {
  grep -rq 'loaded_perl_provider' "$NVIM/lua/config"
  grep -rq 'loaded_ruby_provider' "$NVIM/lua/config"
  grep -rq 'loaded_node_provider' "$NVIM/lua/config"
}

# ── profile wiring ───────────────────────────────────────────────────────────

@test "User Core serves the nvim program fleet-wide" {
  grep -q '"nvim"' "$UCORE"
}

# ── ticket 02: LSP + completion ──────────────────────────────────────────────
# Servers install as system packages in Host Core language-servers, not the
# program and not mason (ADR 0135); the program owns only the config + a guarded
# best-effort Swift.

@test "Host Core declares the added repo language servers (ADR 0135)" {
  local H="$REPO/.installer/hosts/core/profile.jsonc"
  grep -q '"lua-language-server"' "$H"
  grep -q '"svelte-language-server"' "$H"
  grep -q '"vue-language-server"' "$H"
  grep -q '"tailwindcss-language-server"' "$H"
  grep -q '"php"' "$H"                       # phpactor runtime
}

@test "Host Core declares the added AUR language servers (ADR 0135)" {
  local H="$REPO/.installer/hosts/core/profile.jsonc"
  grep -q '"basedpyright"' "$H"
  grep -q '"nixd"' "$H"
  grep -q '"emmet-language-server"' "$H"
}

@test "phpactor installs via the program with php iconv enabled (ADR 0135)" {
  # phpactor's AUR build needs php's iconv extension, so it can't be a bare
  # package (VM-verified). The program enables iconv, then installs it — and it
  # is NOT declared as a bare Host Core package.
  grep -q 'extension=iconv' "$INSTALL"
  grep -q 'needed phpactor' "$INSTALL"
  ! grep -q '"phpactor"' "$REPO/.installer/hosts/core/profile.jsonc"
}

@test "install.sh installs Swift best-effort, never failing the install" {
  grep -q 'swift-bin' "$INSTALL"            # sourcekit-lsp ships with swift-bin
  grep -qE 'print_status warning' "$INSTALL"
}

@test "config wires nvim-lspconfig + native vim.lsp.enable (no mason)" {
  grep -rq 'neovim/nvim-lspconfig' "$NVIM/lua/plugins"
  grep -rq 'vim.lsp.enable' "$NVIM/lua/plugins"
  # no mason plugin (system packages instead, ADR 0135)
  ! grep -rqiE 'mason-org|williamboman/mason|mason\.nvim' "$NVIM/lua"
}

@test "completion is blink.cmp (ADR 0135)" {
  grep -rq 'saghen/blink.cmp' "$NVIM/lua/plugins"
}

@test "solid rides ts_ls; no dedicated solid server" {
  # ts_ls now lives in the Language Registry (ADR 0141), under lua/config.
  grep -rq 'ts_ls' "$NVIM/lua"
  ! grep -rqiE 'solid[_-]?(ls|language)' "$NVIM/lua"
}

@test "vue uses the current vue_ls name, not the deprecated volar" {
  grep -rq 'vue_ls' "$NVIM/lua"
  ! grep -rqw 'volar' "$NVIM/lua"
}

# ── Language Registry (ADR 0141) ─────────────────────────────────────────────
# One table drives lsp/conform/lint/dap; the specs consume it, no inline lists.

@test "the Language Registry table exists and declares the toolchain fields" {
  local R="$NVIM/lua/config/languages.lua"
  [ -f "$R" ]
  grep -q 'lsp =' "$R"
  grep -q 'ts =' "$R"
  grep -q 'formatter =' "$R"
  grep -q 'linter =' "$R"
  grep -q 'dap =' "$R"
}

@test "the registry carries the servers, formatters and linters" {
  local R="$NVIM/lua/config/languages.lua"
  grep -q 'ts_ls' "$R"
  grep -q 'gopls' "$R"
  grep -q 'rust_analyzer' "$R"
  grep -q 'stylua' "$R"
  grep -q 'ruff_format' "$R"
  grep -q 'biome' "$R"
  grep -q 'prettier' "$R"
  grep -q 'biomejs' "$R"
}

@test "lsp/conform/lint/treesitter consume the registry, not inline lists" {
  grep -q 'require("config.languages").servers()' "$NVIM/lua/plugins/lsp.lua"
  grep -q 'require("config.languages").formatters_by_ft()' \
    "$NVIM/lua/plugins/conform.lua"
  grep -q 'require("config.languages").linters_by_ft()' \
    "$NVIM/lua/plugins/lint.lua"
  grep -q 'require("config.languages").parsers()' \
    "$NVIM/lua/plugins/treesitter.lua"
}

# ── Debugging: nvim-dap (ADR 0140) ───────────────────────────────────────────
# Adapters are system packages (Host Core), never mason.

@test "nvim-dap + dap-ui + adapters are declared and lazy on <leader>d" {
  local D="$NVIM/lua/plugins/dap.lua"
  [ -f "$D" ]
  grep -q 'mfussenegger/nvim-dap' "$D"
  grep -q 'rcarriga/nvim-dap-ui' "$D"
  grep -q 'nvim-neotest/nvim-nio' "$D"
  grep -q 'mfussenegger/nvim-dap-python' "$D"
  grep -q 'leoluz/nvim-dap-go' "$D"
  grep -q '"<leader>d' "$D"
  ! grep -qE '^\s*event =' "$D"          # lazy on keys, not an eager event
}

@test "dap wires adapters from the registry; codelldb + pwa-node" {
  local D="$NVIM/lua/plugins/dap.lua"
  grep -q 'require("config.languages").adapters()' "$D"
  grep -q 'codelldb' "$D"
  grep -q 'pwa-node' "$D"
  grep -q 'dap-python' "$D"
  grep -q 'dap-go' "$D"
}

@test "no mason-nvim-dap; adapters are system packages (ADR 0140)" {
  ! grep -rqiE 'mason-nvim-dap|jay-babu/mason' "$NVIM/lua"
}

@test "Host Core declares the DAP adapter packages (ADR 0140)" {
  local H="$REPO/.installer/hosts/core/profile.jsonc"
  grep -q '"delve"' "$H"
  grep -q '"python-debugpy"' "$H"
  grep -q '"codelldb-bin"' "$H"
  grep -q '"vscode-js-debug"' "$H"
}

@test "checkhealth gate loads dap and requires the adapter binaries" {
  local CH="$REPO/.installer/tests/nvim/checkhealth.sh"
  grep -q 'load nvim-dap' "$CH"
  grep -q 'codelldb' "$CH"
  grep -q 'dlv' "$CH"
}

# ── ticket 03: format + lint ─────────────────────────────────────────────────

@test "Host Core declares the formatter/linter packages (ADR 0135)" {
  local H="$REPO/.installer/hosts/core/profile.jsonc"
  grep -q '"stylua"' "$H"
  grep -q '"prettier"' "$H"
  grep -q '"ruff"' "$H"
  grep -q '"biome"' "$H"                     # already present for js/ts
}

@test "formatting via conform, formatters from the registry" {
  local C="$NVIM/lua/plugins/conform.lua"
  grep -q 'stevearc/conform.nvim' "$C"
  grep -q 'formatters_by_ft()' "$C"
  grep -q 'format_on_save' "$C"
  # the biome/prettier/stylua/ruff split lives in the registry
  local R="$NVIM/lua/config/languages.lua"
  grep -q 'stylua' "$R"
  grep -q 'ruff_format' "$R"
  grep -q 'biome' "$R"
  grep -q 'prettier' "$R"
}

@test "linting via nvim-lint, linters from the registry" {
  grep -q 'mfussenegger/nvim-lint' "$NVIM/lua/plugins/lint.lua"
  grep -q 'linters_by_ft()' "$NVIM/lua/plugins/lint.lua"
  local R="$NVIM/lua/config/languages.lua"
  grep -q 'ruff' "$R"
  grep -q 'biomejs' "$R"
}

# ── ticket 04: files & navigation UX ─────────────────────────────────────────

@test "files/nav plugins present: snacks, oil, harpoon" {
  # snacks.explorer replaced neo-tree; oil owns buffer-editing.
  local P="$NVIM/lua/plugins"
  grep -rq 'folke/snacks.nvim' "$P"
  grep -rq 'stevearc/oil.nvim' "$P"
  grep -rq 'ThePrimeagen/harpoon' "$P"
  ! grep -rq 'nvim-neo-tree/neo-tree.nvim' "$P"
}

@test "snacks provides picker, dashboard and notifier" {
  local S="$NVIM/lua/plugins/snacks.lua"
  grep -q 'picker' "$S"
  grep -q 'dashboard' "$S"
  grep -q 'notifier' "$S"
}

# ── ticket 05: chrome, git & editing helpers ─────────────────────────────────

@test "chrome/git/editing plugins present (ticket 05)" {
  # snacks replaced fugitive for git; Emmet is served by its LSP, not a plugin.
  local P="$NVIM/lua/plugins"
  grep -rq 'nvim-lualine/lualine.nvim' "$P"
  grep -rq 'akinsho/bufferline.nvim' "$P"
  grep -rq 'folke/which-key.nvim' "$P"
  grep -rq 'lewis6991/gitsigns.nvim' "$P"
  grep -rq 'echasnovski/mini.ai' "$P"
  grep -rq 'echasnovski/mini.pairs' "$P"
  grep -rq 'kevinhwang91/nvim-ufo' "$P"
  grep -rq 'render-markdown.nvim' "$P"
  grep -rq 'folke/todo-comments.nvim' "$P"
  grep -rq 'mbbill/undotree' "$P"
  ! grep -rq 'tpope/vim-fugitive' "$P"
}

@test "nvim-emmet is dropped; Emmet is served by emmet_language_server" {
  ! grep -rq 'olrtg/nvim-emmet' "$NVIM/lua"
  [ ! -e "$NVIM/lua/plugins/emmet.lua" ]
  grep -q 'emmet_language_server' "$NVIM/lua/config/languages.lua"
}

@test "lualine uses the auto theme (tracks the active palette)" {
  # "auto" derives the bar from the live colorscheme, so it follows any of the 5
  # palettes; a named theme ("catppuccin") warns (no such lualine module ships)
  # and would not track a palette switch.
  grep -q 'theme = "auto"' "$NVIM/lua/plugins/lualine.lua"
}

# ── ticket 06: palettes + follow toggle ──────────────────────────────────────

@test "the five Noctalia builtin palettes are installed" {
  local P="$NVIM/lua/plugins"
  grep -rq 'catppuccin/nvim' "$P"
  grep -rq 'rose-pine/neovim' "$P"
  grep -rq 'folke/tokyonight.nvim' "$P"
  grep -rq 'ellisonleao/gruvbox.nvim' "$P"
  grep -rq 'nord.nvim' "$P"
}

@test "theme module resolves follow_noctalia and persists the static choice" {
  local T="$NVIM/lua/config/theme.lua"
  [ -f "$T" ]
  grep -q 'follow_noctalia' "$T"
  grep -q 'save_choice' "$T"
  grep -q 'apply_static' "$T"
}

@test "the colorscheme picker + follow toggle are mapped" {
  grep -q 'pick_colorscheme' "$NVIM/lua/config/keymaps.lua"
  grep -q 'toggle_follow' "$NVIM/lua/config/keymaps.lua"
}

@test "init applies the theme after plugins load" {
  grep -q 'require("config.theme").setup()' "$NVIM/init.lua"
}

# ── ticket 07: Neovim Theme Template (live bridge) ───────────────────────────
# The config.toml registration + stowed template input are asserted in
# noctalia-stow.bats, beside the pi/kitty/zsh template tests.

@test "seed theme source is Mocha Sapphire base16 (ADR 0136)" {
  local S="$PROG/themes/noctalia.lua"
  [ -f "$S" ]
  grep -q 'base00 = "#1e1e2e"' "$S"          # Mocha base
  grep -q 'base05 = "#cdd6f4"' "$S"          # Mocha text
  grep -q 'accent = "#74c7ec"' "$S"          # sapphire
}

@test "install.sh seeds the generated nvim theme into all three targets" {
  grep -q '"${HOME}/.config/nvim/themes/noctalia.lua"' "$INSTALL"
  grep -q '/etc/skel/.config/nvim/themes/noctalia.lua' "$INSTALL"
  grep -q '/root/.config/nvim/themes/noctalia.lua' "$INSTALL"
}

@test "generated nvim theme is seed-only: gitignored, not in the home bundle" {
  grep -q 'programs/dev/nvim/home/.config/nvim/themes/' "$REPO/.gitignore"
  [ ! -e "$NVIM/themes/noctalia.lua" ]
}

@test "follow path loads the base16 file and live-reloads (ADR 0136)" {
  local N="$NVIM/lua/config/noctalia.lua"
  [ -f "$N" ]
  grep -q 'mini.base16' "$N"
  grep -q 'fs_event' "$N"
  grep -q 'themes/noctalia.lua' "$N"
}

@test "mini.base16 is available for the follow path" {
  grep -rq 'echasnovski/mini.base16' "$NVIM/lua/plugins"
}

# ── ticket 08: acceptance gate (Seam B) ──────────────────────────────────────
# These assert the probe + gate exist and are shaped right; they are RUN against
# a booted config on the arch-combined VM verify-block, not in this static seam.

@test "Seam B probe asserts theme state + follow reload" {
  local PB="$REPO/.installer/tests/nvim/probe.lua"
  [ -f "$PB" ]
  grep -q 'follow_noctalia' "$PB"
  grep -q 'catppuccin' "$PB"
  grep -q '74c7ec' "$PB"
  grep -q 'config.noctalia' "$PB"
}

@test "checkhealth gate script gates on ERROR + in-scope LSPs on PATH" {
  local CH="$REPO/.installer/tests/nvim/checkhealth.sh"
  [ -f "$CH" ]
  [ -x "$CH" ]
  grep -q 'checkhealth' "$CH"
  grep -q 'ERROR' "$CH"
  grep -q 'basedpyright-langserver' "$CH"
  grep -q 'sourcekit-lsp' "$CH"          # optional, noted not failed
}

# ── ticket 09: cutover — single source, old trees retired ────────────────────

@test "home/ is the single source: no repo-root nvim trees (ADR 0134/0135)" {
  # After cutover the served config is the program's home/ only; the old LazyVim
  # tree and the nvim.bak reference are gone, so nothing collides on stow.
  [ ! -e "$REPO/.config/nvim" ]
  [ ! -e "$REPO/.config/nvim.bak" ]
}
