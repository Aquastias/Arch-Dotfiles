-- Feature Audit nvim keybind runner (ADR 0152): one bind per fresh headless
-- nvim, in the user's real config. The key goes through nvim's own input
-- queue (mappings, <leader>, remaps) and the declared effect is judged from a
-- before/after snapshot. Env: FA_KEY FA_MODE FA_EFFECT FA_ARG FA_ID
-- FA_NEEDS (lsp = wait for a client to attach first).
local lhs, mode = os.getenv("FA_KEY"), os.getenv("FA_MODE") or "n"
local effect, arg, id = os.getenv("FA_EFFECT"), os.getenv("FA_ARG") or "", os.getenv("FA_ID")
local errors = {}
local orig = vim.notify
vim.notify = function(m, l, o)
  if l and l >= vim.log.levels.ERROR then errors[#errors + 1] = tostring(m) end
  return orig(m, l, o)
end
local f = vim.fn.tempname() .. ".lua"
local fh = io.open(f, "w")
for i = 1, 40 do fh:write(("local v%d = %d -- word%d\n"):format(i, i, i)) end
fh:close()
vim.cmd("edit " .. f)
vim.api.nvim_win_set_cursor(0, { 10, 6 })
pcall(vim.cmd, "normal! /word\r")   -- a search, for n/N and <Esc>
vim.api.nvim_win_set_cursor(0, { 10, 6 })
vim.wait(300)
if (os.getenv("FA_NEEDS") or ""):find("lsp") then
  vim.wait(15000, function() return #vim.lsp.get_clients({ bufnr = 0 }) > 0 end, 200)
  vim.wait(500)
end
local function snap()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  return { wins = #wins, tabs = #vim.api.nvim_list_tabpages(),
    buf = vim.api.nvim_get_current_buf(), ft = vim.bo.filetype,
    text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
    cur = table.concat(vim.api.nvim_win_get_cursor(0), ","),
    mode = vim.api.nvim_get_mode().mode, hl = vim.v.hlsearch }
end
local prefix = ({ v = "V", x = "V", o = "d", t = "", i = "i", c = ":" })[mode] or ""
if mode == "t" then vim.cmd("terminal") vim.wait(500) vim.cmd("startinsert") end
local b = snap()
vim.v.errmsg = ""
local ok, err = pcall(vim.api.nvim_feedkeys, vim.keycode(prefix .. lhs), "mx", false)
vim.wait(1500)
local a = snap()
local em = vim.v.errmsg
local bad = (not ok and tostring(err)) or errors[1] or (em ~= "" and em) or nil
local function judge()
  if effect == "runs" then return true end
  if effect == "window-opens" then return a.wins > b.wins or a.tabs > b.tabs end
  if effect == "buffer-changes" then return a.buf ~= b.buf or a.ft ~= b.ft end
  if effect == "text-changes" then return a.text ~= b.text end
  if effect == "cursor-moves" then return a.cur ~= b.cur or a.buf ~= b.buf end
  if effect == "mode" then return a.mode:sub(1, 1) == arg end
  if effect == "lua" then
    local fn = load("return " .. arg); local k, v = pcall(fn); return k and v
  end
  return false
end
local line
if bad then line = ("FAIL %s error: %s"):format(id, (tostring(bad):gsub("\n", " ")))
elseif judge() then line = ("PASS %s %s"):format(id, effect)
else line = ("FAIL %s expected %s%s, not observed"):format(id, effect, arg ~= "" and (" " .. arg) or "") end
io.stdout:write(line .. "\n")
vim.cmd("qa!")
