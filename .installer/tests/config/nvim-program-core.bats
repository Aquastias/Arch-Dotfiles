#!/usr/bin/env bats
# Tests: program, LSP, format, lint (split from nvim-program.bats;
# shared setup in nvim-program-helpers.bash)

load nvim-program-helpers


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
  local host_core_profile="$REPO/.installer/hosts/core/profile.jsonc"
  grep -q '"lua-language-server"' "$host_core_profile"
  grep -q '"svelte-language-server"' "$host_core_profile"
  grep -q '"vue-language-server"' "$host_core_profile"
  grep -q '"tailwindcss-language-server"' "$host_core_profile"
  grep -q '"php"' "$host_core_profile"                       # phpactor runtime
}

@test "Host Core declares the added AUR language servers (ADR 0135)" {
  local host_core_profile="$REPO/.installer/hosts/core/profile.jsonc"
  grep -q '"basedpyright"' "$host_core_profile"
  grep -q '"nixd"' "$host_core_profile"
  grep -q '"emmet-language-server"' "$host_core_profile"
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
  local registry_file="$NVIM/lua/config/languages.lua"
  [ -f "$registry_file" ]
  grep -q 'lsp =' "$registry_file"
  grep -q 'ts =' "$registry_file"
  grep -q 'formatter =' "$registry_file"
  grep -q 'linter =' "$registry_file"
  grep -q 'dap =' "$registry_file"
}

@test "the registry carries the servers, formatters and linters" {
  local registry_file="$NVIM/lua/config/languages.lua"
  grep -q 'ts_ls' "$registry_file"
  grep -q 'gopls' "$registry_file"
  grep -q 'rust_analyzer' "$registry_file"
  grep -q 'stylua' "$registry_file"
  grep -q 'ruff_format' "$registry_file"
  grep -q 'biome' "$registry_file"
  grep -q 'prettier' "$registry_file"
  grep -q 'biomejs' "$registry_file"
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
  local plugin_file="$NVIM/lua/plugins/dap.lua"
  [ -f "$plugin_file" ]
  grep -q 'mfussenegger/nvim-dap' "$plugin_file"
  grep -q 'rcarriga/nvim-dap-ui' "$plugin_file"
  grep -q 'nvim-neotest/nvim-nio' "$plugin_file"
  grep -q 'mfussenegger/nvim-dap-python' "$plugin_file"
  grep -q 'leoluz/nvim-dap-go' "$plugin_file"
  grep -q '"<leader>d' "$plugin_file"
  ! grep -qE '^\s*event =' "$plugin_file"          # lazy on keys, not an eager event
}

@test "dap wires adapters + filetypes from the registry; codelldb + pwa-node" {
  local plugin_file="$NVIM/lua/plugins/dap.lua"
  grep -q 'require("config.languages")' "$plugin_file"
  grep -q 'adapters()' "$plugin_file"
  grep -q 'dap_filetypes()' "$plugin_file"   # ft read from the registry, not hardcoded
  grep -q 'codelldb' "$plugin_file"
  grep -q 'pwa-node' "$plugin_file"
  grep -q 'command = "js-debug-dap"' "$plugin_file"   # the bin vscode-js-debug-bin ships
  grep -q 'dap-python' "$plugin_file"
  grep -q 'dap-go' "$plugin_file"
}

@test "no mason-nvim-dap; adapters are system packages (ADR 0140)" {
  ! grep -rqiE 'mason-nvim-dap|jay-babu/mason' "$NVIM/lua"
}

@test "Host Core declares the DAP adapter packages (ADR 0140)" {
  local host_core_profile="$REPO/.installer/hosts/core/profile.jsonc"
  grep -q '"delve"' "$host_core_profile"
  grep -q '"python-debugpy"' "$host_core_profile"
  grep -q '"codelldb-bin"' "$host_core_profile"
  grep -q '"vscode-js-debug-bin"' "$host_core_profile"
}

@test "checkhealth gate loads dap and requires the adapter binaries" {
  local checkhealth_script="$REPO/.installer/tests/nvim/checkhealth.sh"
  grep -q 'load nvim-dap' "$checkhealth_script"
  grep -q 'codelldb' "$checkhealth_script"
  grep -q 'dlv' "$checkhealth_script"
  grep -q 'js-debug-dap' "$checkhealth_script"
}


# ── ticket 03: format + lint ─────────────────────────────────────────────────

@test "Host Core declares the formatter/linter packages (ADR 0135)" {
  local host_core_profile="$REPO/.installer/hosts/core/profile.jsonc"
  grep -q '"stylua"' "$host_core_profile"
  grep -q '"prettier"' "$host_core_profile"
  grep -q '"ruff"' "$host_core_profile"
  grep -q '"biome"' "$host_core_profile"                     # already present for js/ts
}

@test "formatting via conform, formatters from the registry" {
  local plugin_file="$NVIM/lua/plugins/conform.lua"
  grep -q 'stevearc/conform.nvim' "$plugin_file"
  grep -q 'formatters_by_ft()' "$plugin_file"
  grep -q 'format_on_save' "$plugin_file"
  # the biome/prettier/stylua/ruff split lives in the registry
  local registry_file="$NVIM/lua/config/languages.lua"
  grep -q 'stylua' "$registry_file"
  grep -q 'ruff_format' "$registry_file"
  grep -q 'biome' "$registry_file"
  grep -q 'prettier' "$registry_file"
}

@test "every language in use has a formatter (ADR 0151)" {
  local registry_file="$NVIM/lua/config/languages.lua" formatter
  for formatter in shfmt clang_format nixfmt phpcbf xmllint kdlfmt taplo; do
    grep -q "\"$formatter\"" "$registry_file" || { echo "missing $formatter"; false; }
  done
  grep -q '"scss", "less"' "$registry_file"
  local host_core_profile="$REPO/.installer/hosts/core/profile.jsonc"
  for formatter in shfmt taplo-cli kdlfmt nixfmt; do
    grep -q "\"$formatter\"" "$host_core_profile" || { echo "$formatter not in Host Core"; false; }
  done
  grep -q 'needed php-codesniffer' "$INSTALL"
}

@test "shell/kdl/toml format on <leader>cf only, not on save (ADR 0151)" {
  local registry_file="$NVIM/lua/config/languages.lua"
  [ "$(grep -c 'format_on_save = false' "$registry_file")" -eq 3 ]
  grep -q 'manual_format_fts()' "$NVIM/lua/plugins/conform.lua"
}

@test "rest.nvim formats html/xml responses too" {
  grep -q 'prettier --parser html' "$NVIM/lua/plugins/rest.lua"
  grep -q 'xmllint --format -' "$NVIM/lua/plugins/rest.lua"
}

@test "linting via nvim-lint, linters from the registry" {
  grep -q 'mfussenegger/nvim-lint' "$NVIM/lua/plugins/lint.lua"
  grep -q 'linters_by_ft()' "$NVIM/lua/plugins/lint.lua"
  local registry_file="$NVIM/lua/config/languages.lua"
  grep -q 'ruff' "$registry_file"
  grep -q 'biomejs' "$registry_file"
}


# ── ticket 04: files & navigation UX ─────────────────────────────────────────

@test "files/nav plugins present: snacks, oil, harpoon" {
  # snacks.explorer replaced neo-tree; oil owns buffer-editing.
  local plugins_directory="$NVIM/lua/plugins"
  grep -rq 'folke/snacks.nvim' "$plugins_directory"
  grep -rq 'stevearc/oil.nvim' "$plugins_directory"
  grep -rq 'ThePrimeagen/harpoon' "$plugins_directory"
  ! grep -rq 'nvim-neo-tree/neo-tree.nvim' "$plugins_directory"
}

@test "snacks provides picker, dashboard and notifier" {
  local plugin_file="$NVIM/lua/plugins/snacks.lua"
  grep -q 'picker' "$plugin_file"
  grep -q 'dashboard' "$plugin_file"
  grep -q 'notifier' "$plugin_file"
}


# ── ticket 05: chrome, git & editing helpers ─────────────────────────────────

@test "chrome/git/editing plugins present (ticket 05)" {
  # snacks replaced fugitive for git; Emmet is served by its LSP, not a plugin.
  local plugins_directory="$NVIM/lua/plugins"
  grep -rq 'nvim-lualine/lualine.nvim' "$plugins_directory"
  grep -rq 'akinsho/bufferline.nvim' "$plugins_directory"
  grep -rq 'folke/which-key.nvim' "$plugins_directory"
  grep -rq 'lewis6991/gitsigns.nvim' "$plugins_directory"
  grep -rq 'echasnovski/mini.ai' "$plugins_directory"
  grep -rq 'echasnovski/mini.pairs' "$plugins_directory"
  grep -rq 'kevinhwang91/nvim-ufo' "$plugins_directory"
  grep -rq 'render-markdown.nvim' "$plugins_directory"
  grep -rq 'folke/todo-comments.nvim' "$plugins_directory"
  grep -rq 'mbbill/undotree' "$plugins_directory"
  ! grep -rq 'tpope/vim-fugitive' "$plugins_directory"
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
  local plugins_directory="$NVIM/lua/plugins"
  grep -rq 'catppuccin/nvim' "$plugins_directory"
  grep -rq 'rose-pine/neovim' "$plugins_directory"
  grep -rq 'folke/tokyonight.nvim' "$plugins_directory"
  grep -rq 'ellisonleao/gruvbox.nvim' "$plugins_directory"
  grep -rq 'nord.nvim' "$plugins_directory"
}

@test "theme module resolves follow_noctalia and persists the static choice" {
  local theme_file="$NVIM/lua/config/theme.lua"
  [ -f "$theme_file" ]
  grep -q 'follow_noctalia' "$theme_file"
  grep -q 'save_choice' "$theme_file"
  grep -q 'apply_static' "$theme_file"
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
  local theme_file="$PROG/themes/noctalia.lua"
  [ -f "$theme_file" ]
  grep -q 'base00 = "#1e1e2e"' "$theme_file"          # Mocha base
  grep -q 'base05 = "#cdd6f4"' "$theme_file"          # Mocha text
  grep -q 'accent = "#74c7ec"' "$theme_file"          # sapphire
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
  local noctalia_file="$NVIM/lua/config/noctalia.lua"
  [ -f "$noctalia_file" ]
  grep -q 'mini.base16' "$noctalia_file"
  grep -q 'fs_event' "$noctalia_file"
  grep -q 'themes/noctalia.lua' "$noctalia_file"
}

@test "mini.base16 is available for the follow path" {
  grep -rq 'echasnovski/mini.base16' "$NVIM/lua/plugins"
}


# ── ticket 08: acceptance gate (Seam B) ──────────────────────────────────────
# These assert the probe + gate exist and are shaped right; they are RUN against
# a booted config on the arch-combined VM verify-block, not in this static seam.

@test "Seam B probe asserts theme state + follow reload" {
  local probe_script="$REPO/.installer/tests/nvim/probe.lua"
  [ -f "$probe_script" ]
  grep -q 'follow_noctalia' "$probe_script"
  grep -q 'catppuccin' "$probe_script"
  grep -q '74c7ec' "$probe_script"
  grep -q 'config.noctalia' "$probe_script"
}

@test "checkhealth gate script gates on ERROR + in-scope LSPs on PATH" {
  local checkhealth_script="$REPO/.installer/tests/nvim/checkhealth.sh"
  [ -f "$checkhealth_script" ]
  [ -x "$checkhealth_script" ]
  grep -q 'checkhealth' "$checkhealth_script"
  grep -q 'ERROR' "$checkhealth_script"
  grep -q 'basedpyright-langserver' "$checkhealth_script"
  grep -q 'sourcekit-lsp' "$checkhealth_script"          # optional, noted not failed
}


# ── ticket 09: cutover — single source, old trees retired ────────────────────

@test "home/ is the single source: no repo-root nvim trees (ADR 0134/0135)" {
  # After cutover the served config is the program's home/ only; the old LazyVim
  # tree and the nvim.bak reference are gone, so nothing collides on stow.
  [ ! -e "$REPO/.config/nvim" ]
  [ ! -e "$REPO/.config/nvim.bak" ]
}


# ── IDE expansion: git diffview (ticket 04) ──────────────────────────────────

@test "diffview is declared, lazy on :Diffview* and mapped under <leader>g" {
  local plugin_file="$NVIM/lua/plugins/diffview.lua"
  [ -f "$plugin_file" ]
  grep -q 'sindrets/diffview.nvim' "$plugin_file"
  grep -q 'DiffviewFileHistory' "$plugin_file"
  grep -q 'cmd =' "$plugin_file"
  grep -q '"<leader>gd"' "$plugin_file"
  ! grep -qE '^\s*event =' "$plugin_file"
}

@test "gitsigns has a line-blame toggle and hunk navigation" {
  local plugin_file="$NVIM/lua/plugins/gitsigns.lua"
  grep -q 'toggle_current_line_blame' "$plugin_file"
  grep -q '"<leader>gt"' "$plugin_file"
  grep -q 'nav_hunk' "$plugin_file"
  grep -q '"]h"' "$plugin_file"
}
