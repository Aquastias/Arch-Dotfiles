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

-- Buffer cycling (bufferline).
map("n", "<Tab>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next buffer" })
map("n", "<S-Tab>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Prev buffer" })

-- Editing.
map("v", "J", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })
map("n", "J", "mzJ`z", { desc = "Join line, keep cursor" })
map("v", "<", "<gv", { desc = "Indent left, keep selection" })
map("v", ">", ">gv", { desc = "Indent right, keep selection" })
map("x", "<leader>p", [["_dP]], { desc = "Paste without clobbering register" })
map(
  "n",
  "<leader>rw",
  [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
  { desc = "Replace word under cursor" }
)

-- Navigation stays centered.
map("n", "<C-d>", "<C-d>zz", { desc = "Half page down (centered)" })
map("n", "<C-u>", "<C-u>zz", { desc = "Half page up (centered)" })
map("n", "n", "nzzzv", { desc = "Next match (centered)" })
map("n", "N", "Nzzzv", { desc = "Prev match (centered)" })

-- Repo-handy.
map("n", "<leader>cx", "<cmd>!chmod +x %<cr>", { silent = true, desc = "Make file executable" })
map("n", "<leader>yp", function()
  local path = vim.fn.expand("%:~")
  vim.fn.setreg("+", path)
  vim.notify("Copied: " .. path)
end, { desc = "Copy file path" })
map("n", "<leader><cr>", "<cmd>source %<cr>", { desc = "Source current file" })
