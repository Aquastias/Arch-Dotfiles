require("config.core") -- Load core
require("config.lazy") -- Load lazy

-- Load last saved colorscheme, fallback to default if not set yet
local ok, _ = pcall(require, "colorscheme")
if not ok then
	vim.cmd.colorscheme("rose-pine")
end

-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
