local map = vim.keymap.set
map("n", "<leader>w", "<cmd>write<cr>", { desc = "Write buffer" }) -- comment
map({ "n", "t" }, "<C-/>", function() end, { desc = "Toggle terminal" })
vim.keymap.set(
  "v",
  "J",
  ":m '>+1<cr>gv=gv",
  { desc = "Move selection down" }
)
local lspmap = function(keys, fn, desc) end
for i = 1, 3 do
  map("n", "<leader>" .. i, function() end, { desc = "Harpoon " .. i })
end
return {
  "x/plugin",
  keys = {
    { "<leader>xx", "<cmd>Trouble<cr>", desc = "Diags" },
    {
      "s",
      mode = { "n", "x" },
      function() end,
      desc = "Flash",
    },
  },
}
