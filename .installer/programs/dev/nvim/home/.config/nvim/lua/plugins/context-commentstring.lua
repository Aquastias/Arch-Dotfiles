-- nvim-ts-context-commentstring: make Neovim's native `gc` comment correctly in
-- embedded regions (JSX/Vue/Svelte), where a single commentstring is wrong. No
-- mappings of its own — it feeds the built-in commenting by overriding how
-- Neovim resolves the `commentstring` filetype option.
return {
  "JoosepAlviste/nvim-ts-context-commentstring",
  event = { "BufReadPost", "BufNewFile" },
  opts = { enable_autocmd = false },
  config = function(_, opts)
    require("ts_context_commentstring").setup(opts)
    vim.g.skip_ts_context_commentstring_module = true
    -- Native `gc` reads commentstring via vim.filetype.get_option; route that
    -- through the treesitter-context calculation.
    local get_option = vim.filetype.get_option
    vim.filetype.get_option = function(filetype, option)
      if option ~= "commentstring" then
        return get_option(filetype, option)
      end
      local ctx = require("ts_context_commentstring.internal")
      return ctx.calculate_commentstring() or get_option(filetype, option)
    end
  end,
}
