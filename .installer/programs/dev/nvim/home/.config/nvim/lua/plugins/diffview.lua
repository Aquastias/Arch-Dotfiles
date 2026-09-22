-- diffview.nvim: the two jobs lazygit is worse at — a side-by-side merge
-- conflict resolver and a navigable file/branch history with real syntax.
-- lazygit stays the daily driver; it lazy-loads on its :Diffview* commands, so
-- it costs nothing at startup. Maps live under the <leader>g (git) group.
return {
  "sindrets/diffview.nvim",
  cmd = {
    "DiffviewOpen",
    "DiffviewClose",
    "DiffviewFileHistory",
    "DiffviewToggleFiles",
    "DiffviewFocusFiles",
  },
  keys = {
    { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diff/conflicts" },
    { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
    { "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "Repo history" },
    { "<leader>gx", "<cmd>DiffviewClose<cr>", desc = "Diffview close" },
  },
  opts = {},
}
