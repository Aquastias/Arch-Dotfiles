-- Treesitter on the `main` branch (the Neovim 0.12 rewrite). `master`'s query
-- predicates throw "attempt to call method 'range'" on every injection parse
-- (markdown, hover floats) under 0.12. `main`'s API differs: no configs.setup —
-- .install{} for parsers, a FileType autocmd for highlight + indent; ufo folds.
-- Parser list comes from the Language Registry (ADR 0141).
local ensure = require("config.languages").parsers()

return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  lazy = false,
  build = ":TSUpdate",
  config = function()
    require("nvim-treesitter").install(ensure)

    -- Start highlight + TS indent per buffer; pcall so a missing parser no-ops.
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
