-- Set leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

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
-- NOTE: Buffers
-- ============================================================
vim.keymap.set("n", "<Tab>", "<cmd>bnext<CR>", vim.tbl_extend("force", opts, { desc = "Next buffer" }))
vim.keymap.set("n", "<S-Tab>", "<cmd>bprevious<CR>", vim.tbl_extend("force", opts, { desc = "Prev buffer" }))
vim.keymap.set("n", "<leader>x", "<cmd>bdelete!<CR>", vim.tbl_extend("force", opts, { desc = "Close buffer" }))
vim.keymap.set("n", "<leader>b", "<cmd>enew<CR>", vim.tbl_extend("force", opts, { desc = "New buffer" }))

-- ============================================================
-- NOTE: Splits
-- ============================================================
vim.keymap.set("n", "<leader>sv", "<C-w>v", { desc = "Split vertically" })
vim.keymap.set("n", "<leader>sh", "<C-w>s", { desc = "Split horizontally" })
vim.keymap.set("n", "<leader>se", "<C-w>=", { desc = "Equal split size" })
vim.keymap.set("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close split" })

-- Navigate splits
vim.keymap.set("n", "<C-h>", "<cmd>wincmd h<CR>", opts)
vim.keymap.set("n", "<C-j>", "<cmd>wincmd j<CR>", opts)
vim.keymap.set("n", "<C-k>", "<cmd>wincmd k<CR>", opts)
vim.keymap.set("n", "<C-l>", "<cmd>wincmd l<CR>", opts)

-- Resize splits
vim.keymap.set("n", "<Up>", "<cmd>resize -2<CR>", opts)
vim.keymap.set("n", "<Down>", "<cmd>resize +2<CR>", opts)
vim.keymap.set("n", "<Left>", "<cmd>vertical resize -2<CR>", opts)
vim.keymap.set("n", "<Right>", "<cmd>vertical resize +2<CR>", opts)

-- ============================================================
-- NOTE: Tabs
-- ============================================================
vim.keymap.set("n", "<leader>to", "<cmd>tabnew<CR>", { desc = "New tab" })
vim.keymap.set("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Close tab" })
vim.keymap.set("n", "<leader>tn", "<cmd>tabn<CR>", { desc = "Next tab" })
vim.keymap.set("n", "<leader>tp", "<cmd>tabp<CR>", { desc = "Prev tab" })
vim.keymap.set("n", "<leader>tf", "<cmd>tabnew %<CR>", { desc = "Open current buf in new tab" })

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
vim.keymap.set({ "n", "v" }, "<leader>d", [["_d]], { desc = "Delete without yanking" })
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

-- Format with LSP
vim.keymap.set("n", "<leader>f", vim.lsp.buf.format, { desc = "Format buffer" })

-- Tmux sessionizer
vim.keymap.set("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>", { desc = "Tmux sessionizer" })

-- ============================================================
-- NOTE: Diagnostics
-- ============================================================
vim.keymap.set("n", "[d", function()
	vim.diagnostic.jump({ count = -1, float = true })
end, { desc = "Prev diagnostic" })

vim.keymap.set("n", "]d", function()
	vim.diagnostic.jump({ count = 1, float = true })
end, { desc = "Next diagnostic" })

vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Diagnostics list" })

-- ============================================================
-- NOTE: Autocmds
-- ============================================================
vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight on yank",
	group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
	callback = function()
		vim.hl.on_yank()
	end,
})
