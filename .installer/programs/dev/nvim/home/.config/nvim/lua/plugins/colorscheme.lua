-- Static default look (ADR 0136): Catppuccin Mocha with the accent overridden
-- to Catppuccin sapphire (#74c7ec). Palette switching among the five Noctalia
-- builtins and the follow_noctalia live path arrive in tickets 06/07.
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "mocha",
      background = { dark = "mocha" },
      term_colors = true,
      custom_highlights = function(c)
        local accent = "#74c7ec" -- Catppuccin Mocha sapphire
        return {
          Cursor = { bg = accent },
          MatchParen = { fg = accent, bold = true },
          Search = { bg = accent, fg = c.base },
          IncSearch = { bg = accent, fg = c.base },
          CurSearch = { bg = accent, fg = c.base },
          PmenuSel = { bg = accent, fg = c.base },
          FloatBorder = { fg = accent },
          Title = { fg = accent, bold = true },
          Directory = { fg = accent },
        }
      end,
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      vim.cmd.colorscheme("catppuccin")
    end,
  },
}
