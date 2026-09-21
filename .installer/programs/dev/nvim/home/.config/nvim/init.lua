-- Served Neovim config (ADR 0135). Hand-rolled on lazy.nvim; not LazyVim,
-- not vim.pack. Targets stable Neovim 0.12.x.

-- Neovim 0.12's native vim.pack.get() creates an empty site/pack/core/opt on
-- first call, which then makes :checkhealth's lazy + vim.pack sections warn
-- (stray package dir, absent lockfile). This config is lazy.nvim, and its only
-- caller is catppuccin's integration auto-detect — which also reads lazy's
-- plugin list, so an empty return loses nothing. Stub it so nothing creates the
-- stray dir and both checks stay green. (ADR 0135)
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
