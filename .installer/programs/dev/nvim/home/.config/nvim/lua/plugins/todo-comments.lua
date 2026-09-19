-- todo-comments (ADR 0135): highlight + navigate TODO/FIX/NOTE tags.
return {
  "folke/todo-comments.nvim",
  event = { "BufReadPre", "BufNewFile" },
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = { signs = true },
}
