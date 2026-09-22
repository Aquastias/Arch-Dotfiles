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
  opts = function()
    -- formatters_by_ft comes from the Language Registry (ADR 0141).
    return {
      formatters_by_ft = require("config.languages").formatters_by_ft(),
      default_format_opts = { lsp_format = "fallback" },
      format_on_save = { timeout_ms = 1000, lsp_format = "fallback" },
    }
  end,
}
