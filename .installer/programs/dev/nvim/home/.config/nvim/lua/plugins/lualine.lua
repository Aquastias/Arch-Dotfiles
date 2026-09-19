-- lualine (ADR 0135): statusline themed to catppuccin so the accent tracks the
-- active colorscheme. Global statusline (one bar for all splits).
return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "VeryLazy",
  opts = {
    options = {
      theme = "catppuccin",
      globalstatus = true,
      section_separators = "",
      component_separators = "",
    },
  },
}
