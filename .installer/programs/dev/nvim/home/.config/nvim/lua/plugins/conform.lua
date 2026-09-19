-- Formatting (ADR 0135): conform.nvim. biome for js/ts/jsx/tsx/json/css,
-- prettier for html/svelte/vue/yaml/md, stylua for lua, ruff for python; native
-- rustfmt/gofmt/zigfmt for the systems languages. Tools install as system
-- packages (Host Core), no mason. Falls back to the LSP formatter otherwise.
return {
  "stevearc/conform.nvim",
  event = { "BufWritePre" },
  cmd = { "ConformInfo" },
  keys = {
    {
      "<leader>cf",
      function()
        require("conform").format({ async = true, lsp_format = "fallback" })
      end,
      mode = { "n", "v" },
      desc = "Format buffer",
    },
  },
  opts = {
    formatters_by_ft = {
      lua = { "stylua" },
      python = { "ruff_format" },
      javascript = { "biome" },
      typescript = { "biome" },
      javascriptreact = { "biome" },
      typescriptreact = { "biome" },
      json = { "biome" },
      jsonc = { "biome" },
      css = { "biome" },
      html = { "prettier" },
      svelte = { "prettier" },
      vue = { "prettier" },
      yaml = { "prettier" },
      markdown = { "prettier" },
      rust = { "rustfmt" },
      go = { "gofmt" },
      zig = { "zigfmt" },
    },
    default_format_opts = { lsp_format = "fallback" },
    format_on_save = { timeout_ms = 1000, lsp_format = "fallback" },
  },
}
