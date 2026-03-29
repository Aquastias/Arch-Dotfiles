-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Disable space default behavior
vim.keymap.set({ "n", "v" }, "<Space>", "<Nop>", { silent = true })

local opts = { noremap = true, silent = true }

-- ============================================================
-- NOTE: Files
-- ============================================================
vim.keymap.set("n", "<C-s>", "<cmd>w<CR>", vim.tbl_extend("force", opts, { desc = "Save file" }))
vim.keymap.set(
  "n",
  "<leader>sn",
  "<cmd>noautocmd w<CR>",
  vim.tbl_extend("force", opts, { desc = "Save without formatting" })
)
vim.keymap.set("n", "<C-q>", "<cmd>q<CR>", vim.tbl_extend("force", opts, { desc = "Quit" }))
vim.keymap.set("n", "<leader>yp", function()
  local path = vim.fn.expand("%:~")
  vim.fn.setreg("+", path)
  vim.notify("Copied: " .. path, vim.log.levels.INFO)
end, { desc = "Copy file path to clipboard" })

-- Source current file
vim.keymap.set("n", "<leader><CR>", "<cmd>so<CR>", { desc = "Source current file" })

-- Make file executable
vim.keymap.set("n", "<leader>cx", "<cmd>!chmod +x %<CR>", { silent = true, desc = "Make file executable" })

-- ============================================================
-- NOTE: Editing
-- ============================================================
-- Move lines in visual mode
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line down" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line up" })

-- Join line without moving cursor
vim.keymap.set("n", "J", "mzJ`z", { desc = "Join line" })

-- Indent and stay in visual mode
vim.keymap.set("v", "<", "<gv", opts)
vim.keymap.set("v", ">", ">gv", opts)

-- Don't copy on delete
vim.keymap.set({ "n", "v" }, "<leader>dd", [["_d]], { desc = "Delete without yanking" })
vim.keymap.set("n", "x", '"_x', opts)

-- Paste without overwriting register
vim.keymap.set("v", "p", '"_dP', opts)
vim.keymap.set("x", "<leader>P", '"_dP', { desc = "Paste without overwriting register" })

-- Yank to system clipboard
vim.keymap.set("n", "<leader>Y", '"+Y', opts)

-- Replace word under cursor globally
vim.keymap.set(
  "n",
  "<leader>rw",
  [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
  { desc = "Replace word under cursor globally" }
)

-- Toggle line wrap
vim.keymap.set("n", "<leader>lw", "<cmd>set wrap!<CR>", { desc = "Toggle line wrap" })

-- ============================================================
-- NOTE: Navigation
-- ============================================================
-- Scroll and center
vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Scroll down centered" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Scroll up centered" })

-- Search and center
vim.keymap.set("n", "n", "nzzzv", opts)
vim.keymap.set("n", "N", "Nzzzv", opts)

-- ============================================================
-- NOTE: Misc
-- ============================================================
-- Escape shortcuts
vim.keymap.set("i", "<C-c>", "<Esc>", { desc = "Escape insert mode" })
vim.keymap.set("n", "<C-c>", "<cmd>nohl<CR>", { silent = true, desc = "Clear search highlight" })

-- Disable Q
vim.keymap.set("n", "Q", "<nop>")
