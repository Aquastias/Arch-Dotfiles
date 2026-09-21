-- bufferline (ADR 0135): buffers as tabs, LSP diagnostics inline. Highlights
-- come from catppuccin's bufferline integration.
return {
  "akinsho/bufferline.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "VeryLazy",
  opts = {
    options = {
      diagnostics = "nvim_lsp",
      separator_style = "thin",
      show_buffer_close_icons = false,
      show_close_icon = false,
      -- Hide the bar until there are ≥2 buffers, so the dashboard / a single
      -- file isn't topped by an empty dark tabline strip.
      always_show_bufferline = false,
    },
  },
}
