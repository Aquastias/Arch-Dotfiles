-- nvim-ufo (ADR 0135): IDE-grade folding. Provider chain LSP -> treesitter ->
-- indent; files open unfolded; readable fold summary; peek; a fold gutter with
-- nerd-font markers. LSP folds need the foldingRange capability (lsp.lua).
return {
  "kevinhwang91/nvim-ufo",
  dependencies = { "kevinhwang91/promise-async" },
  event = "BufReadPost",
  init = function()
    vim.o.foldcolumn = "1"
    vim.o.foldlevel = 99
    vim.o.foldlevelstart = 99
    vim.o.foldenable = true
    -- Fold gutter markers, by codepoint so the glyphs stay ASCII in source and
    -- cannot be stripped (▾ open, ▸ closed). Each fillchars field must be
    -- exactly one character or Neovim raises E1511.
    vim.opt.fillchars:append({
      foldopen = "\u{25be}",
      foldclose = "\u{25b8}",
      foldsep = " ",
      fold = " ",
      eob = " ",
    })
  end,
  keys = {
    {
      "zR",
      function() require("ufo").openAllFolds() end,
      desc = "Open all folds",
    },
    {
      "zM",
      function() require("ufo").closeAllFolds() end,
      desc = "Close all folds",
    },
    {
      "zr",
      function() require("ufo").openFoldsExceptKinds() end,
      desc = "Open folds (incremental)",
    },
    {
      "zm",
      function() require("ufo").closeFoldsWith() end,
      desc = "Close folds (incremental)",
    },
    {
      "zK",
      function() require("ufo").peekFoldedLinesUnderCursor() end,
      desc = "Peek fold",
    },
  },
  opts = function()
    -- LSP -> treesitter -> indent fallback chain (ufo's canonical pattern).
    local function select(bufnr)
      local function fallback(err, provider)
        if type(err) == "string" and err:match("UfoFallbackException") then
          return require("ufo").getFolds(bufnr, provider)
        end
        return require("promise").reject(err)
      end
      return require("ufo")
        .getFolds(bufnr, "lsp")
        :catch(function(err)
          return fallback(err, "treesitter")
        end)
        :catch(function(err)
          return fallback(err, "indent")
        end)
    end

    -- Fold summary: first line + "⋯ N lines", right-aligned.
    local function fold_text(virt_text, lnum, end_lnum, width, truncate)
      local out = {}
      local suffix = ("  ⋯ %d lines"):format(end_lnum - lnum)
      local target = width - vim.fn.strdisplaywidth(suffix)
      local cur = 0
      for _, chunk in ipairs(virt_text) do
        local text, hl = chunk[1], chunk[2]
        local w = vim.fn.strdisplaywidth(text)
        if target > cur + w then
          table.insert(out, chunk)
        else
          text = truncate(text, target - cur)
          table.insert(out, { text, hl })
          w = vim.fn.strdisplaywidth(text)
          if cur + w < target then
            suffix = suffix .. (" "):rep(target - cur - w)
          end
          break
        end
        cur = cur + w
      end
      table.insert(out, { suffix, "MoreMsg" })
      return out
    end

    return {
      provider_selector = function()
        return select
      end,
      fold_virt_text_handler = fold_text,
    }
  end,
}
