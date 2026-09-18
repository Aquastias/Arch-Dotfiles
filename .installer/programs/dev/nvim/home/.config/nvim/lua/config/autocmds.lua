-- Highlight text on yank (uses vim.hl on 0.11+, falls back to vim.highlight).
local hl = vim.hl or vim.highlight
vim.api.nvim_create_autocmd("TextYankPost", {
  group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
  callback = function()
    hl.on_yank()
  end,
})
