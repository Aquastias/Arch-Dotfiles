-- Feature Audit nvim probe (ADR 0152): run inside the user's real config via
-- `nvim --headless -c "luafile probe.lua"`. Prints PASS|FAIL|SKIP lines.
-- Proves: every lazy spec is installed and loads, :checkhealth has no ERROR,
-- and every Language Registry (ADR 0141) row's LSP attaches, parser loads,
-- formatter/linter/debug adapter is available — offline.
local out = {}
local function emit(s, id, msg)
  out[#out + 1] = s .. " " .. id .. " " .. (msg or "")
end
local function pass(id, m) emit("PASS", id, m) end
local function fail(id, m)
  emit("FAIL", id, (tostring(m or "")):gsub("\n", " "))
end
local function skip(id, m) emit("SKIP", id, m) end
-- audit.sh sets FA_HOST_CORE=0 on a host not inheriting Host Core packages
local host_core = os.getenv("FA_HOST_CORE") ~= "0"

-- capture error notifications raised while loading/probing
local errors = {}
local orig_notify = vim.notify
vim.notify = function(msg, level, o)
  if level and level >= vim.log.levels.ERROR then
    errors[#errors + 1] = tostring(msg)
  end
  return orig_notify(msg, level, o)
end

local ext = {
  lua = "lua", python = "py", typescript = "ts", javascript = "js",
  typescriptreact = "tsx", javascriptreact = "jsx", json = "json",
  jsonc = "jsonc", go = "go", rust = "rs", c = "c", cpp = "cpp", sh = "sh",
  bash = "sh", zsh = "zsh", nix = "nix", php = "php", svelte = "svelte",
  vue = "vue", html = "html", css = "css", scss = "scss", less = "less",
  yaml = "yaml", toml = "toml", markdown = "md", zig = "zig", kdl = "kdl",
  xml = "xml", http = "http", astro = "astro", tex = "tex", typst = "typ",
  dockerfile = "Dockerfile", make = "mk", cmake = "cmake", sql = "sql",
}
local body = {
  lua = "local x = 1\nreturn x\n", python = "x = 1\nprint(x)\n",
  go = "package main\n\nfunc main() {}\n", rust = "fn main() {}\n",
  c = "int main(void) { return 0; }\n", cpp = "int main() { return 0; }\n",
  json = "{ \"a\": 1 }\n", jsonc = "{ \"a\": 1 }\n", sh = "echo hi\n",
  php = "<?php\necho 1;\n", html = "<!doctype html>\n<p>x</p>\n",
}
local dir = vim.fn.tempname(); vim.fn.mkdir(dir, "p")
-- a project root, as servers that only attach inside one need (phpactor:
-- composer.json/.git, eslint: an eslint config)
vim.fn.system({ "git", "-C", dir, "init", "-q" })
for f, s in pairs({ ["composer.json"] = "{}\n",
  ["eslint.config.js"] = "export default [];\n" }) do
  local fh = io.open(dir .. "/" .. f, "w"); fh:write(s); fh:close()
end
local function sample(ft)
  local e = ext[ft]; if not e then return nil end
  local f = dir .. "/sample." .. e
  local fh = io.open(f, "w"); fh:write(body[ft] or "x\n"); fh:close()
  vim.cmd("edit " .. vim.fn.fnameescape(f))
  if vim.bo.filetype ~= ft then vim.bo.filetype = ft end
  return vim.api.nvim_get_current_buf()
end
local function exe(cmd)
  if type(cmd) == "function" then return true end
  if type(cmd) == "table" then cmd = cmd[1] end
  return type(cmd) == "string" and vim.fn.executable(cmd) == 1
end

-- 1. plugins: installed + load without error
local ok_lazy, lazy_cfg = pcall(require, "lazy.core.config")
if not ok_lazy then
  fail("nvim-lazy", "lazy.nvim not loadable")
else
  local names = {}
  for name, p in pairs(lazy_cfg.plugins) do
    names[#names + 1] = name
    if not (p._ and p._.installed) then
      fail("nvim-plugin-" .. name, "not installed")
    end
  end
  local before = #errors
  local ok, err = pcall(function()
    require("lazy").load({ plugins = names })
  end)
  if not ok then fail("nvim-plugins-load", err)
  elseif #errors > before then fail("nvim-plugins-load", errors[before + 1])
  else pass("nvim-plugins-load", #names .. " plugins loaded") end
end

-- 2. registry toolchain
local ok_reg, langs = pcall(require, "config.languages")
if not ok_reg then fail("nvim-registry", langs) else
  for _, p in ipairs(langs.parsers()) do
    local ok = pcall(vim.treesitter.language.add, p)
    if ok then pass("nvim-ts-" .. p, "parser loads")
    else fail("nvim-ts-" .. p, "parser missing") end
  end
  -- The toolchain is Host Core (ADR 0135): a host that does not inherit it
  -- (packages.inherit: false) has none of it by design (Probe Gate).
  if not host_core then
    skip("nvim-toolchain", "Host Core not inherited (packages.inherit false)")
  else
  for _, s in ipairs(langs.servers()) do
    local cfg = vim.lsp.config[s]
    if not cfg then fail("nvim-lsp-" .. s, "no lsp config")
    elseif not exe(cfg.cmd) then
      fail("nvim-lsp-" .. s,
        "server binary not found: " .. vim.inspect(cfg.cmd))
    else
      local ft = (cfg.filetypes or {})[1]
      local buf = ft and sample(ft)
      if not buf then skip("nvim-lsp-" .. s, "no sample for " .. tostring(ft))
      else
        local ok = vim.wait(8000, function()
          return #vim.lsp.get_clients({ bufnr = buf, name = s }) > 0
        end, 200)
        if ok then pass("nvim-lsp-" .. s, "attached on " .. ft)
        else
          fail("nvim-lsp-" .. s, "did not attach to a " .. ft .. " buffer")
        end
      end
    end
  end
  local ok_c, conform = pcall(require, "conform")
  for ft, fmts in pairs(langs.formatters_by_ft()) do
    local buf = sample(ft)
    for _, f in ipairs(fmts) do
      local id = "nvim-fmt-" .. f .. "-" .. ft
      if not ok_c or not buf then skip(id, "no conform/sample")
      else
        local info = conform.get_formatter_info(f, buf)
        if not info.available then
          fail(id, info.available_msg or "unavailable")
        else
          -- really format the sample: a present-but-broken tool fails here
          local ok, e = pcall(conform.format, { bufnr = buf,
            formatters = { f }, async = false, timeout_ms = 10000 })
          if ok then pass(id, "formats a " .. ft .. " sample")
          else fail(id, "format failed: " .. tostring(e)) end
        end
      end
    end
  end
  local ok_l, lint = pcall(require, "lint")
  for ft, ls in pairs(langs.linters_by_ft()) do
    for _, l in ipairs(ls) do
      local d = ok_l and lint.linters[l]
      if type(d) == "function" then d = d() end
      if not d then fail("nvim-lint-" .. l, "linter not defined")
      elseif exe(d.cmd) then pass("nvim-lint-" .. l, "available")
      else
        fail("nvim-lint-" .. l, "binary not found: " .. vim.inspect(d.cmd))
      end
    end
  end
  local ok_d, dap = pcall(require, "dap")
  for _, a in ipairs(langs.adapters()) do
    if not ok_d then fail("nvim-dap-" .. a, "nvim-dap not loadable") else
      -- registry key → the adapter dap.lua registers for it (ADR 0140)
      local name = ({ rust = "codelldb", c = "codelldb", cpp = "codelldb",
        js = "pwa-node" })[a] or a
      local found = dap.adapters[name]
      if not found then fail("nvim-dap-" .. a, "no adapter registered")
      elseif type(found) == "table" and found.command and not exe(found.command)
        and not (found.executable and exe(found.executable.command)) then
        fail("nvim-dap-" .. a, "adapter binary not found")
      else pass("nvim-dap-" .. a, "adapter registered") end
    end
  end
  end
end

-- 3. :checkhealth — every ERROR line is a finding, except the ones only a
-- headless probe sees: the dashboard sets up on a bare UI start, and the
-- image check asks this TTY (not kitty) for the graphics protocol.
local headless_only = { "setup did not run", "kitty graphics protocol" }
local ok_h = pcall(vim.cmd, "silent checkhealth")
if ok_h then
  local seen = {}
  for _, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if l:match("ERROR") and not seen[l] then
      seen[l] = true
      local msg, hl = (l:gsub("^%s*[-*]?%s*", "")), false
      for _, p in ipairs(headless_only) do
        hl = hl or msg:find(p, 1, true) ~= nil
      end
      if hl then skip("nvim-health", "headless only: " .. msg)
      elseif not host_core then skip("nvim-health", "no Host Core: " .. msg)
      else fail("nvim-health", msg) end
    end
  end
  if next(seen) == nil then pass("nvim-health", "no ERROR in :checkhealth") end
end

-- 4. keymaps the config defines at runtime but the static parse cannot see
-- (a loop-built `"<leader>" .. i`, maps set inside plugin setup callbacks):
-- written as bind rows to $FA_LIVE for audit.sh to plan + test. Only maps
-- whose defining script / callback lives in the config dir count.
local plan = {}
local pf = os.getenv("FA_DIR") .. "/binds-plan.jsonl"
for line in io.lines(pf) do
  local ok, r = pcall(vim.json.decode, line)
  if ok and r.chord then plan[vim.fn.keytrans(vim.keycode(r.chord))] = true end
end
local cfgdir = vim.fn.stdpath("config")
local function origin(km)
  if km.callback then
    return ((debug.getinfo(km.callback, "S").source or "")
      :gsub("^@", ""))
  end
  local si = km.sid and km.sid > 0 and vim.fn.getscriptinfo({ sid = km.sid })
  return si and si[1] and si[1].name or ""
end
local live = io.open(os.getenv("FA_LIVE"), "w")
for _, m in ipairs({ "n", "v", "x", "o", "i", "t", "c" }) do
  for _, km in ipairs(vim.api.nvim_get_keymap(m)) do
    local k = vim.fn.keytrans(vim.keycode(km.lhs))
    if not plan[k] and km.lhs:sub(1, 5) ~= "<Plug"
      and origin(km):find(cfgdir, 1, true) then
      plan[k] = true
      live:write(("nvim\t%s\t%s %s\n"):format(km.lhs, m, km.desc or ""))
    end
  end
end
live:close()

-- stdout carries nvim's own messages in headless mode: report via a file
local fh_out = io.open(os.getenv("FA_OUT"), "w")
fh_out:write(table.concat(out, "\n") .. "\n")
fh_out:close()
vim.cmd("qa!")
