-- Served Neovim config (ADR 0135). Hand-rolled on lazy.nvim; not LazyVim,
-- not vim.pack. Targets stable Neovim 0.12.x.
require("config.options")
require("config.keymaps")
require("config.autocmds")
require("config.lazy")
-- Apply the colorscheme after plugins load (static, or Noctalia-follow).
require("config.theme").setup()
