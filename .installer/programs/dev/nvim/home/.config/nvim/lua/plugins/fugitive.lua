-- vim-fugitive (ADR 0135): raw git from inside nvim; the status buffer.
return {
  "tpope/vim-fugitive",
  cmd = { "Git", "G" },
  keys = {
    { "<leader>gg", "<cmd>Git<cr>", desc = "Git status (fugitive)" },
  },
}
