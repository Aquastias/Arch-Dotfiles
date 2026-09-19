-- oil.nvim (ADR 0135): edit the filesystem as a buffer. Primary explorer for
-- quick moves; neo-tree is the sidebar view.
return {
  "stevearc/oil.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  lazy = false,
  opts = {
    default_file_explorer = true,
    delete_to_trash = true,
    view_options = { show_hidden = true },
    keymaps = { ["q"] = "actions.close" },
  },
  keys = {
    { "-", "<cmd>Oil<cr>", desc = "Open parent dir (oil)" },
    {
      "<leader>-",
      function()
        require("oil").toggle_float()
      end,
      desc = "Oil (float)",
    },
  },
}
