-- lualine (ADR 0135): `theme = "auto"` derives the bar from the ACTIVE
-- colorscheme's highlights, so the accent tracks whichever of the 5 palettes is
-- live (and follow-mode) — a named theme (e.g. "catppuccin") both warns on
-- startup (no such lualine theme module ships) and wouldn't track a palette
-- switch. Global statusline (one bar for all splits).
return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "VeryLazy",
  opts = {
    options = {
      theme = "auto",
      globalstatus = true,
      section_separators = "",
      component_separators = "",
    },
  },
}
