-- Seam B probe (ticket 08, ADR 0136): boot the served config headless and
-- assert observable theme state, including the follow_noctalia live reload.
-- Run: nvim --headless -c "luafile <this file>"  (loads init; exits non-zero on
-- failure). Note: `-l` does NOT load init.lua, so it cannot be used here.
local errors = {}
local function check(cond, msg)
  if not cond then
    errors[#errors + 1] = msg
  end
end

local function fg(group)
  return vim.api.nvim_get_hl(0, { name = group }).fg
end

-- Static default: follow off, catppuccin, sapphire accent.
check(vim.g.follow_noctalia == false, "follow_noctalia must default to false")
check(
  (vim.g.colors_name or ""):match("^catppuccin") ~= nil,
  "default scheme must be catppuccin, got " .. tostring(vim.g.colors_name)
)
check(fg("MatchParen") == tonumber("74c7ec", 16), "accent must be sapphire")

-- Live follow: write a generated palette, flip on, re-apply, expect its accent.
local dir = vim.fn.stdpath("config") .. "/themes"
vim.fn.mkdir(dir, "p")
local out = assert(io.open(dir .. "/noctalia.lua", "w"))
out:write([[return {
  base00="#101010", base01="#181818", base02="#202020", base03="#282828",
  base04="#585858", base05="#d8d8d8", base06="#e8e8e8", base07="#f8f8f8",
  base08="#ab4642", base09="#dc9656", base0A="#f7ca88", base0B="#a1b56c",
  base0C="#86c1b9", base0D="#7cafc2", base0E="#ba8baf", base0F="#a16946",
  accent="#ff0000",
}
]])
out:close()
vim.g.follow_noctalia = true
require("config.noctalia").apply()
check(fg("MatchParen") == tonumber("ff0000", 16), "follow reload must repaint")

if #errors > 0 then
  io.stderr:write("PROBE FAIL:\n  " .. table.concat(errors, "\n  ") .. "\n")
  vim.cmd("cquit 1")
end
io.stdout:write("PROBE OK\n")
vim.cmd("qall!")
