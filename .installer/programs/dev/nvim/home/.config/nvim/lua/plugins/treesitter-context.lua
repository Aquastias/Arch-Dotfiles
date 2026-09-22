-- nvim-treesitter-context: pin the current function/class signature at the top
-- while scrolling a long body (sticky scroll). Lazy on read.
return {
  "nvim-treesitter/nvim-treesitter-context",
  event = { "BufReadPost", "BufNewFile" },
  opts = {
    max_lines = 3,
    multiline_threshold = 1,
  },
}
