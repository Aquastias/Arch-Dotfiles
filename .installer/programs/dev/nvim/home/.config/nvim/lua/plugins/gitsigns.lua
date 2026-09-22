-- gitsigns (ADR 0135): signs, staged signs, and inline blame.
return {
  "lewis6991/gitsigns.nvim",
  event = { "BufReadPre", "BufNewFile" },
  keys = {
    {
      "<leader>gt",
      function()
        require("gitsigns").toggle_current_line_blame()
      end,
      desc = "Git: toggle line blame",
    },
    {
      "]h",
      function()
        require("gitsigns").nav_hunk("next")
      end,
      desc = "Next git hunk",
    },
    {
      "[h",
      function()
        require("gitsigns").nav_hunk("prev")
      end,
      desc = "Prev git hunk",
    },
  },
  opts = {
    signs = {
      add = { text = "▎" },
      change = { text = "▎" },
      delete = { text = "" },
      topdelete = { text = "" },
      changedelete = { text = "▎" },
      untracked = { text = "▎" },
    },
    signs_staged_enable = true,
    current_line_blame = false,
  },
}
