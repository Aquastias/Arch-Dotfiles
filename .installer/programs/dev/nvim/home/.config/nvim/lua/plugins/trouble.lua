-- trouble.nvim: a project-wide diagnostics / quickfix / symbols list. Lazy on
-- the <leader>x group + :Trouble. Pairs with todo-comments (its Trouble source)
-- for the todo list.
return {
  "folke/trouble.nvim",
  cmd = "Trouble",
  keys = {
    { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics (Trouble)" },
    { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer diagnostics (Trouble)" },
    { "<leader>xt", "<cmd>Trouble todo toggle<cr>", desc = "Todo list (Trouble)" },
    { "<leader>xq", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix (Trouble)" },
    { "<leader>xl", "<cmd>Trouble loclist toggle<cr>", desc = "Location list (Trouble)" },
    { "<leader>xs", "<cmd>Trouble symbols toggle focus=false<cr>", desc = "Symbols (Trouble)" },
  },
  opts = {},
}
