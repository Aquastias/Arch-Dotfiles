-- Theme control (ADR 0136). Resolves the startup colorscheme from the
-- follow_noctalia toggle: off → a static Noctalia builtin palette (default
-- Catppuccin Mocha + sapphire accent), persisted across sessions; on → the
-- live-follow path, wired by lua/config/noctalia.lua (ticket 07). Falls back to
-- static whenever the follow module is absent or errors.
local M = {}

M.builtins = { "catppuccin", "rose-pine", "tokyonight", "gruvbox", "nord" }
M.default = "catppuccin"

local state_file = vim.fn.stdpath("state") .. "/colorscheme"

local function read_choice()
  local f = io.open(state_file, "r")
  if not f then
    return M.default
  end
  local name = f:read("*l")
  f:close()
  if name and #name > 0 then
    return name
  end
  return M.default
end

-- Persist the chosen static palette (survives restarts).
function M.save_choice(name)
  local f = io.open(state_file, "w")
  if f then
    f:write(name .. "\n")
    f:close()
  end
end

-- Apply the static colorscheme (follow_noctalia = false path).
function M.apply_static()
  if not pcall(vim.cmd.colorscheme, read_choice()) then
    pcall(vim.cmd.colorscheme, M.default)
  end
end

-- Apply the theme according to the current follow_noctalia state.
function M.setup()
  if vim.g.follow_noctalia then
    local ok, noctalia = pcall(require, "config.noctalia")
    if ok and noctalia.apply then
      noctalia.apply()
      return
    end
  end
  M.apply_static()
end

-- Pick a static palette via the snacks picker and persist it.
function M.pick_colorscheme()
  Snacks.picker.colorschemes({
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.cmd.colorscheme(item.text)
        M.save_choice(item.text)
      end
    end,
  })
end

-- Flip follow_noctalia at runtime and re-apply.
function M.toggle_follow()
  vim.g.follow_noctalia = not vim.g.follow_noctalia
  M.setup()
  vim.notify("follow_noctalia = " .. tostring(vim.g.follow_noctalia))
end

return M
