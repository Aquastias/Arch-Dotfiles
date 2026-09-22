-- Served Neovim config (ADR 0135). Hand-rolled on lazy.nvim; not LazyVim,
-- not vim.pack. Targets stable Neovim 0.12.x.

-- Neovim 0.12's vim.pack.get() makes an empty site/pack/core/opt on first call
-- → :checkhealth warns (stray dir, no lockfile). catppuccin's auto-detect (its
-- only caller) also reads lazy's list, so an empty stub is safe. (ADR 0135)
if vim.fn.has("nvim-0.12.0") == 1 and vim.pack then
  vim.pack.get = function()
    return {}
  end
end

require("config.options")
require("config.keymaps")
require("config.autocmds")
require("config.lazy")
-- Apply the colorscheme after plugins load (static, or Noctalia-follow).
require("config.theme").setup()
