-- Linting (ADR 0135): nvim-lint fills the diagnostics the LSPs don't. biome for
-- js/ts family, ruff for python. biome only runs where the project carries a
-- biome config, so a biome-less repo is not flagged.
return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local lint = require("lint")

    -- linters_by_ft comes from the Language Registry (ADR 0141).
    lint.linters_by_ft = require("config.languages").linters_by_ft()

    -- Only run biome inside a project that configures it.
    lint.linters.biomejs.condition = function(ctx)
      return vim.fs.find(
        { "biome.json", "biome.jsonc" },
        { path = ctx.filename, upward = true }
      )[1] ~= nil
    end

    local grp = vim.api.nvim_create_augroup("nvim-lint", { clear = true })
    vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave", "BufEnter" }, {
      group = grp,
      callback = function()
        if vim.bo.buftype == "" then
          lint.try_lint()
        end
      end,
    })
  end,
}
