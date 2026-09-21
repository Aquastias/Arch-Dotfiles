-- Treesitter on the `main` branch (the Neovim 0.12 rewrite). The old `master`
-- branch's query predicates call a treesitter API 0.12 removed, throwing
-- "attempt to call method 'range' (a nil value)" on every injection parse
-- (markdown, LSP hover floats). `main` fixes that, but has a different API:
-- no `configs.setup` — install via `.install{}`, and enable highlighting +
-- treesitter indent per buffer from a FileType autocmd. Folding stays with ufo.
local ensure = {
  "lua",
  "vim",
  "vimdoc",
  "bash",
  "markdown",
  "markdown_inline",
  "json",
  "yaml",
  -- Web set (matches the served LSPs) + regex/doc parsers snacks expects.
  "regex",
  "css",
  "scss",
  "html",
  "javascript",
  "typescript",
  "tsx",
  "svelte",
  "vue",
  "latex",
  "typst",
}

return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  lazy = false,
  build = ":TSUpdate",
  config = function()
    require("nvim-treesitter").install(ensure)

    -- Start highlighting + TS indent for any buffer whose filetype maps to an
    -- installed parser. pcall so a not-yet-installed parser is a silent no-op.
    local function start(buf)
      local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
      if lang and pcall(vim.treesitter.start, buf, lang) then
        vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end
    end

    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("ts_start", { clear = true }),
      callback = function(ev)
        start(ev.buf)
      end,
    })

    -- Buffers already loaded before this config ran (e.g. a file argument).
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        start(buf)
      end
    end
  end,
}
