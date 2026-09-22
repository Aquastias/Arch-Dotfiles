-- grug-far.nvim: a VS Code-style search/replace panel with live matches across
-- the repo (ripgrep-backed) where snacks' grep only finds. Lazy on command.
-- Maps under the <leader>s (search) group.
return {
  "MagicDuck/grug-far.nvim",
  cmd = "GrugFar",
  keys = {
    {
      "<leader>sr",
      function()
        require("grug-far").open()
      end,
      mode = "n",
      desc = "Search & replace (project)",
    },
    {
      "<leader>sr",
      function()
        require("grug-far").with_visual_selection()
      end,
      mode = "v",
      desc = "Search & replace (selection)",
    },
  },
  opts = {},
}
