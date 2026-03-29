-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- UI / behavior overrides
vim.o.cursorline = false
vim.o.scrolloff = 4
vim.o.sidescrolloff = 8
vim.o.conceallevel = 0
vim.o.cmdheight = 1

-- Editing improvements
vim.o.whichwrap = "bs<>[]hl"
vim.o.breakindent = true
vim.opt.iskeyword:append("-")
vim.opt.formatoptions:remove({ "c", "r", "o" })

-- Disable unused providers (performance)
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

-- Enable this option to avoid conflicts with Prettier.
vim.g.lazyvim_prettier_needs_config = true
