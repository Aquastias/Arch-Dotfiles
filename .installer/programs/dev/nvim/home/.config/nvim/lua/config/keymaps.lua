-- Base keymaps. Plugin-specific maps live with their plugin specs.
local map = vim.keymap.set

map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
map("n", "<leader>w", "<cmd>write<cr>", { desc = "Write buffer" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit window" })

-- Window navigation.
map("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

-- Leave terminal mode.
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- Theme control (ADR 0136): pick a static palette / toggle Noctalia-follow.
map("n", "<leader>uC", function()
  require("config.theme").pick_colorscheme()
end, { desc = "Pick colorscheme" })
map("n", "<leader>uN", function()
  require("config.theme").toggle_follow()
end, { desc = "Toggle follow Noctalia" })
