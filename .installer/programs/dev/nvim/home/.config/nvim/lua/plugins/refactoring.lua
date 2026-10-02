-- refactoring.nvim: WebStorm-style, treesitter-aware refactors — extract
-- function/variable, inline variable/function. Lazy on the <leader>r
-- (refactor) keys. Each refactor is an operator (expr map → `g@`): on a
-- visual selection it acts at once, in normal mode it takes a motion.
local function op(fn)
  return function() return require("refactoring")[fn]() end
end

return {
  "ThePrimeagen/refactoring.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  keys = {
    { "<leader>re", op("extract_func"), mode = { "n", "x" }, expr = true,
      desc = "Extract function" },
    { "<leader>rf", op("extract_func_to_file"), mode = { "n", "x" },
      expr = true, desc = "Extract function to file" },
    { "<leader>rv", op("extract_var"), mode = { "n", "x" }, expr = true,
      desc = "Extract variable" },
    { "<leader>ri", op("inline_var"), mode = { "n", "x" }, expr = true,
      desc = "Inline variable" },
    { "<leader>rI", op("inline_func"), mode = { "n", "x" }, expr = true,
      desc = "Inline function" },
    -- No <leader>rr / select_refactor: the plugin's picker calls `async.run`,
    -- which resolves to promise-async's (nvim-ufo dep) top-level `async` module
    -- that has no `run` → E5108. The direct maps above cover every refactor.
    -- Upstream dropped Extract Block, so <leader>rb is gone with it.
  },
  opts = {},
}
