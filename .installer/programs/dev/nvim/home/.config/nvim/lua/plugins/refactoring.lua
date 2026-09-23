-- refactoring.nvim: WebStorm-style, treesitter-aware refactors from a visual
-- selection — extract function/variable/block, inline variable. Lazy on the
-- <leader>r (refactor) keys.
return {
  "ThePrimeagen/refactoring.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  keys = {
    {
      "<leader>re",
      function() require("refactoring").refactor("Extract Function") end,
      mode = "x",
      desc = "Extract function",
    },
    {
      "<leader>rf",
      function()
        require("refactoring").refactor("Extract Function To File")
      end,
      mode = "x",
      desc = "Extract function to file",
    },
    {
      "<leader>rv",
      function() require("refactoring").refactor("Extract Variable") end,
      mode = "x",
      desc = "Extract variable",
    },
    {
      "<leader>ri",
      function() require("refactoring").refactor("Inline Variable") end,
      mode = { "n", "x" },
      desc = "Inline variable",
    },
    {
      "<leader>rb",
      function() require("refactoring").refactor("Extract Block") end,
      mode = "n",
      desc = "Extract block",
    },
    -- No <leader>rr / select_refactor: the plugin's picker calls `async.run`,
    -- which resolves to promise-async's (nvim-ufo dep) top-level `async` module
    -- that has no `run` → E5108. The direct maps above cover every refactor.
  },
  opts = {},
}
