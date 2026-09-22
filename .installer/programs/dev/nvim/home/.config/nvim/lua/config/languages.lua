-- Language Registry (ADR 0141): the single source of truth for the per-language
-- toolchain. One row per language, each declaring its {lsp, ts, formatter,
-- linter, dap} (all optional). The lsp / conform / lint / dap plugin specs
-- CONSUME this table instead of carrying their own inline lists, so adding a
-- language is one row here. Data, not behaviour: each consumer maps a row into
-- its own plugin shape (vim.lsp.enable, formatters_by_ft, linters_by_ft, dap).
--
--   lsp       lspconfig server name(s) turned on via vim.lsp.enable
--   ts        treesitter parser(s) to install
--   ft        filetype(s) the formatter/linter apply to
--   formatter conform formatter(s), keyed onto every ft above
--   linter    nvim-lint linter(s), keyed onto every ft above
--   dap       debug-adapter key (see dap.lua; ADR 0140), core-five only
--
-- clangd (c/cpp) and cross-cutting web servers (tailwind/emmet/eslint) appear as
-- their own rows; the lsp consumer de-dupes, so a server named twice enables
-- once. Parser-only rows (vimdoc/regex/latex/typst) carry just `ts`.
local registry = {
  lua = { lsp = "lua_ls", ts = { "lua" }, ft = { "lua" }, formatter = { "stylua" } },
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
  json = { lsp = "jsonls", ts = { "json" }, ft = { "json", "jsonc" }, formatter = { "biome" } },
  css = { lsp = "cssls", ts = { "css", "scss" }, ft = { "css" }, formatter = { "biome" } },
  html = { lsp = "html", ts = { "html" }, ft = { "html" }, formatter = { "prettier" } },
  yaml = { lsp = "yamlls", ts = { "yaml" }, ft = { "yaml" }, formatter = { "prettier" } },
  markdown = { ts = { "markdown", "markdown_inline" }, ft = { "markdown" }, formatter = { "prettier" } },
  bash = { lsp = "bashls", ts = { "bash" } },
  -- .http/.rest API files (kulala); no LSP, just the parser + filetype.
  http = { ts = { "http" } },
  go = { lsp = "gopls", ft = { "go" }, formatter = { "gofmt" }, dap = "go" },
  rust = { lsp = "rust_analyzer", ft = { "rust" }, formatter = { "rustfmt" }, dap = "rust" },
  zig = { lsp = "zls", ft = { "zig" }, formatter = { "zigfmt" } },
  c = { lsp = "clangd", dap = "c" },
  cpp = { lsp = "clangd", dap = "cpp" },
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

-- De-duped list of lspconfig server names to vim.lsp.enable.
function M.servers()
  local out, seen = {}, {}
  for _, spec in pairs(registry) do
    local l = spec.lsp
    if l then
      for _, name in ipairs(type(l) == "table" and l or { l }) do
        if not seen[name] then
          seen[name] = true
          out[#out + 1] = name
        end
      end
    end
  end
  return out
end

-- De-duped list of treesitter parsers to install.
function M.parsers()
  local out, seen = {}, {}
  for _, spec in pairs(registry) do
    for _, p in ipairs(spec.ts or {}) do
      if not seen[p] then
        seen[p] = true
        out[#out + 1] = p
      end
    end
  end
  return out
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

-- De-duped list of debug-adapter keys wired across the registry (ADR 0140).
function M.adapters()
  local out, seen = {}, {}
  for _, spec in pairs(registry) do
    if spec.dap and not seen[spec.dap] then
      seen[spec.dap] = true
      out[#out + 1] = spec.dap
    end
  end
  return out
end

return M
