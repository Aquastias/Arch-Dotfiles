-- Formatting (ADR 0135): conform.nvim. biome for js/ts/jsx/tsx/json/css,
-- prettier for html/scss/svelte/vue/yaml/md, stylua for lua, ruff for python,
-- nixfmt, phpcbf, xmllint, clang-format; native rustfmt/gofmt/zigfmt.
-- shfmt/kdlfmt/taplo are manual-only (<leader>cf): on save they'd rewrite the
-- repo's hand-formatted shell/niri/noctalia files (ADR 0151). Tools install as
-- system packages (Host Core), no mason. Falls back to the LSP formatter.
local save_opts = { timeout_ms = 1000, lsp_format = "fallback" }

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
    local manual = require("config.languages").manual_format_fts()
    return {
      formatters_by_ft = require("config.languages").formatters_by_ft(),
      formatters = {
        -- phpcbf defaults to the PEAR standard; PSR-12 is the PHP norm.
        phpcbf = { prepend_args = { "--standard=PSR12" } },
      },
      default_format_opts = { lsp_format = "fallback" },
      format_on_save = function(buf)
        if manual[vim.bo[buf].filetype] then return end
        return save_opts
      end,
    }
  end,
}
