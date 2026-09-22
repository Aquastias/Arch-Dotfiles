-- Language Registry (ADR 0141): the single source of truth for the per-language
-- toolchain. One row per language, each declaring its {lsp, ts, formatter,
-- linter, dap} (all optional). The lsp / conform / lint / dap plugin specs
-- CONSUME this table instead of carrying their own inline lists, so adding a
-- language is one row here. Data, not behaviour: each consumer maps a row into
-- its own plugin shape (vim.lsp.enable, formatters_by_ft, linters_by_ft, dap).
--
--   lsp       lspconfig server name(s) turned on via vim.lsp.enable
--   ts        treesitter parser(s) to install
--   ft        filetype(s) the formatter/linter/dap apply to
--   formatter conform formatter(s), keyed onto every ft above
--   linter    nvim-lint linter(s), keyed onto every ft above
--   dap       debug-adapter key (see dap.lua; ADR 0140), core-five only
--
-- clangd (c/cpp) and the cross-cutting web servers (tailwind/emmet/eslint) get
-- their own rows; the lsp consumer de-dupes, so a server named twice enables
-- once. Parser-only rows (vimdoc/regex/latex/typst) carry just `ts`.
local registry = {
  lua = {
    lsp = "lua_ls",
    ts = { "lua" },
    ft = { "lua" },
    formatter = { "stylua" },
  },
  python = {
    lsp = "basedpyright",
    ft = { "python" },
    formatter = { "ruff_format" },
    linter = { "ruff" },
    dap = "python",
  },
  nix = { lsp = "nixd" },
  php = { lsp = "phpactor" },
  svelte = {
    lsp = "svelte",
    ts = { "svelte" },
    ft = { "svelte" },
    formatter = { "prettier" },
    linter = { "biomejs" },
  },
  vue = {
    lsp = "vue_ls",
    ts = { "vue" },
    ft = { "vue" },
    formatter = { "prettier" },
  },
  typescript = {
    lsp = "ts_ls",
    ts = { "javascript", "typescript", "tsx" },
    ft = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
    formatter = { "biome" },
    linter = { "biomejs" },
    dap = "js",
  },
  json = {
    lsp = "jsonls",
    ts = { "json" },
    ft = { "json", "jsonc" },
    formatter = { "biome" },
  },
  css = {
    lsp = "cssls",
    ts = { "css", "scss" },
    ft = { "css" },
    formatter = { "biome" },
  },
  html = {
    lsp = "html",
    ts = { "html" },
    ft = { "html" },
    formatter = { "prettier" },
  },
  yaml = {
    lsp = "yamlls",
    ts = { "yaml" },
    ft = { "yaml" },
    formatter = { "prettier" },
  },
  markdown = {
    ts = { "markdown", "markdown_inline" },
    ft = { "markdown" },
    formatter = { "prettier" },
  },
  bash = { lsp = "bashls", ts = { "bash" } },
  -- .http/.rest API files (kulala); no LSP, just the parser + filetype.
  http = { ts = { "http" } },
  go = { lsp = "gopls", ft = { "go" }, formatter = { "gofmt" }, dap = "go" },
  rust = {
    lsp = "rust_analyzer",
    ft = { "rust" },
    formatter = { "rustfmt" },
    dap = "rust",
  },
  zig = { lsp = "zls", ft = { "zig" }, formatter = { "zigfmt" } },
  c = { lsp = "clangd", ft = { "c" }, dap = "c" },
  cpp = { lsp = "clangd", ft = { "cpp" }, dap = "cpp" },
  -- Cross-cutting web servers (attach by their own lspconfig filetypes).
  tailwind = { lsp = "tailwindcss" },
  emmet = { lsp = "emmet_language_server" },
  eslint = { lsp = "eslint" },
  -- Parser-only editor infra.
  vimdoc = { ts = { "vim", "vimdoc" } },
  regex = { ts = { "regex" } },
  latex = { ts = { "latex" } },
  typst = { ts = { "typst" } },
}

local M = { registry = registry }

-- De-duped, order-stable list of every value of `field` across the rows;
-- `field` may hold a string or a list — both flatten the same way.
local function collect(field)
  local out, seen = {}, {}
  for _, spec in pairs(registry) do
    local v = spec[field]
    if v ~= nil then
      for _, name in ipairs(type(v) == "table" and v or { v }) do
        if not seen[name] then
          seen[name] = true
          out[#out + 1] = name
        end
      end
    end
  end
  return out
end

-- lspconfig servers to vim.lsp.enable.
function M.servers()
  return collect("lsp")
end

-- treesitter parsers to install.
function M.parsers()
  return collect("ts")
end

-- debug-adapter keys wired across the registry (ADR 0140).
function M.adapters()
  return collect("dap")
end

-- filetype -> tool list, from the given row field ("formatter" | "linter").
local function by_ft(field)
  local out = {}
  for _, spec in pairs(registry) do
    if spec[field] and spec.ft then
      for _, ft in ipairs(spec.ft) do
        out[ft] = spec[field]
      end
    end
  end
  return out
end

function M.formatters_by_ft()
  return by_ft("formatter")
end

function M.linters_by_ft()
  return by_ft("linter")
end

-- adapter key -> filetypes it debugs, so dap.lua reads ft from the registry
-- rather than re-hardcoding it (keeps "add a language is one row" true).
function M.dap_filetypes()
  local out = {}
  for _, spec in pairs(registry) do
    if spec.dap and spec.ft then
      local fts = out[spec.dap] or {}
      for _, ft in ipairs(spec.ft) do
        fts[#fts + 1] = ft
      end
      out[spec.dap] = fts
    end
  end
  return out
end

return M
