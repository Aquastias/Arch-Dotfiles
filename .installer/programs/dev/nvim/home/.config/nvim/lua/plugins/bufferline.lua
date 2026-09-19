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
    },
  },
}
