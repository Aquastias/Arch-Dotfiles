-- Noctalia follow path (ADR 0136). When follow_noctalia is on, load the base16
-- palette Noctalia renders into ~/.config/nvim/themes/, apply it via
-- mini.base16 (full-coverage truecolor), overlay the primary accent, and
-- fs_event-watch the file so a live palette change repaints mid-session. Falls
-- back to the static default when the generated file is missing.
local M = {}

local gen = vim.fn.stdpath("config") .. "/themes/noctalia.lua"
local watching = false

local function load_palette()
  local ok, p = pcall(dofile, gen)
  if ok and type(p) == "table" and p.base00 then
    return p
  end
  return nil
end

local function watch()
  if watching then
    return
  end
  local dir = vim.fn.stdpath("config") .. "/themes"
  vim.fn.mkdir(dir, "p")
  local w = vim.uv.new_fs_event()
  if not w then
    return
  end
  watching = true
  w:start(
    dir,
    {},
    vim.schedule_wrap(function()
      if vim.g.follow_noctalia then
        M.apply()
      end
    end)
  )
end

function M.apply()
  local p = load_palette()
  if not p then
    require("config.theme").apply_static()
    watch()
    return
  end
  -- mini.base16 is loaded on demand (follow mode is rare); force lazy to put it
  -- on the rtp before requiring, and fall back to static if it is unavailable.
  pcall(function()
    require("lazy").load({ plugins = { "mini.base16" } })
  end)
  local ok, base16 = pcall(require, "mini.base16")
  if not ok then
    require("config.theme").apply_static()
    watch()
    return
  end
  base16.setup({
    palette = {
      base00 = p.base00,
      base01 = p.base01,
      base02 = p.base02,
      base03 = p.base03,
      base04 = p.base04,
      base05 = p.base05,
      base06 = p.base06,
      base07 = p.base07,
      base08 = p.base08,
      base09 = p.base09,
      base0A = p.base0A,
      base0B = p.base0B,
      base0C = p.base0C,
      base0D = p.base0D,
      base0E = p.base0E,
      base0F = p.base0F,
    },
  })
  if p.accent then
    local hl = vim.api.nvim_set_hl
    hl(0, "MatchParen", { fg = p.accent, bold = true })
    hl(0, "Title", { fg = p.accent, bold = true })
    hl(0, "FloatBorder", { fg = p.accent })
  end
  watch()
end

return M
