-- Feature Audit nvim keybind runner (ADR 0152): one bind per fresh headless
-- nvim, in the user's real config. The key goes through nvim's own input
-- queue (mappings, <leader>, remaps) and the declared effect is judged from a
-- before/after snapshot. Env: FA_KEY FA_MODE FA_EFFECT FA_ARG FA_ID FA_OUT
-- FA_NEEDS (lsp = wait for a client; ft:<x> = a <x> sample instead of Lua).
-- The sample lives in a throwaway git repo (git maps need one) and has
-- foldable blocks (fold maps need them).
local lhs, mode = os.getenv("FA_KEY"), os.getenv("FA_MODE") or "n"
local effect, id = os.getenv("FA_EFFECT"), os.getenv("FA_ID")
local arg = os.getenv("FA_ARG") or ""
local needs = os.getenv("FA_NEEDS") or ""
local errors = {}
local orig = vim.notify
vim.notify = function(m, l, o)
  if l and l >= vim.log.levels.ERROR then errors[#errors + 1] = tostring(m) end
  return orig(m, l, o)
end

local repo = vim.fn.tempname()
vim.fn.mkdir(repo, "p")
local ft = needs:match("ft:(%w+)")
local f, body
if ft == "http" then
  f = repo .. "/sample.http"
  body = { "GET http://127.0.0.1:9/fa-audit", "" }
else
  f = repo .. "/sample.lua"
  body = {}
  for i = 1, 6 do
    body[#body + 1] = ("local function f%d(x) -- word%d"):format(i, i)
    for j = 1, 4 do
      body[#body + 1] = ("  local v%d = x + %d -- word"):format(j, j)
    end
    body[#body + 1] = "  return x"
    body[#body + 1] = "end"
  end
end
vim.fn.writefile(body, f)
vim.fn.system({ "git", "-C", repo, "init", "-q" })
vim.fn.system({ "git", "-C", repo, "add", "." })
vim.fn.system({ "git", "-C", repo, "-c", "user.name=fa", "-c",
  "user.email=fa@audit", "commit", "-qm", "fa" })
vim.fn.writefile(vim.list_extend(vim.deepcopy(body), { "-- edit" }), f)
vim.cmd("cd " .. vim.fn.fnameescape(repo))
vim.cmd("edit " .. vim.fn.fnameescape(f))
vim.api.nvim_win_set_cursor(0, { 3, 8 })
pcall(vim.cmd, "normal! /word\r")   -- a search, for n/N and <Esc>
vim.api.nvim_win_set_cursor(0, { 3, 8 })
vim.wait(300)
if needs:find("lsp") then
  vim.wait(15000, function()
    return #vim.lsp.get_clients({ bufnr = 0 }) > 0
  end, 200)
  vim.wait(500)
end

local function snap()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  return { wins = #wins, tabs = #vim.api.nvim_list_tabpages(),
    buf = vim.api.nvim_get_current_buf(), ft = vim.bo.filetype,
    text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
    cur = table.concat(vim.api.nvim_win_get_cursor(0), ","),
    mode = vim.api.nvim_get_mode().mode }
end
-- visual maps act on a word selection; operator-pending maps follow `d`
local prefix = ({ v = "viw", x = "viw", o = "d", i = "i", c = ":" })[mode]
  or ""
if mode == "t" then vim.cmd("terminal") vim.wait(500) vim.cmd("startinsert") end
local b = snap()
vim.v.errmsg = ""
local ok, err = pcall(vim.api.nvim_feedkeys, vim.keycode(prefix .. lhs),
  "mx", false)
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
    local fn = load("return " .. arg)
    local k, v = pcall(fn)
    return k and v
  end
  return false
end
local line
if bad then
  line = ("FAIL %s error: %s"):format(id, (tostring(bad):gsub("\n", " ")))
elseif judge() then line = ("PASS %s %s"):format(id, effect)
else
  line = ("FAIL %s expected %s%s, not observed"):format(id, effect,
    arg ~= "" and (" " .. arg) or "")
end
-- stdout carries nvim's own messages in headless mode: report via a file
local fh_out = io.open(os.getenv("FA_OUT"), "a")
fh_out:write(line .. "\n")
fh_out:close()
vim.cmd("qa!")
