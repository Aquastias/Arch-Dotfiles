-- The five Noctalia builtin palettes (ADR 0136) as switchable colorschemes.
-- catppuccin (mocha + sapphire accent) is the default; the active scheme is
-- applied by lua/config/theme.lua, which also persists the user's choice.
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
  },
  { "rose-pine/neovim", name = "rose-pine", lazy = false, opts = {} },
  { "folke/tokyonight.nvim", lazy = false, opts = { style = "night" } },
  { "ellisonleao/gruvbox.nvim", lazy = false, opts = {} },
  { "gbprod/nord.nvim", lazy = false, opts = {} },
}
