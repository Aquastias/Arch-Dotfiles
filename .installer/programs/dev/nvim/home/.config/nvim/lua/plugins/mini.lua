-- mini.nvim modules (ADR 0135): mini.ai (better text objects) + mini.pairs
-- (autopairs). Grouped as one author's modules.
return {
  {
    "echasnovski/mini.ai",
    event = "VeryLazy",
    -- Treesitter textobject QUERIES (not on treesitter's main branch) power the
    -- af/ac function/class def objects below. Query-provider only, first-party.
    dependencies = {
      { "nvim-treesitter/nvim-treesitter-textobjects", branch = "main" },
    },
    opts = function()
      local ai = require("mini.ai")
      return {
        custom_textobjects = {
          f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
          c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
          o = ai.gen_spec.treesitter({
            a = { "@block.outer", "@conditional.outer", "@loop.outer" },
            i = { "@block.inner", "@conditional.inner", "@loop.inner" },
          }),
        },
      }
    end,
  },
  {
    "echasnovski/mini.pairs",
    event = "InsertEnter",
    opts = {},
  },
  {
    -- Surround under the `gs` prefix (not the default `s`), so `s` stays free
    -- for flash's jump motion (the LazyVim resolution of that clash).
    "echasnovski/mini.surround",
    event = "VeryLazy",
    opts = {
      mappings = {
        add = "gsa",
        delete = "gsd",
        find = "gsf",
        find_left = "gsF",
        highlight = "gsh",
        replace = "gsr",
        update_n_lines = "gsn",
      },
    },
  },
  -- Base16 engine for the Noctalia follow path (ADR 0136); loaded on require by
  -- config/noctalia.lua only when follow_noctalia is on.
  { "echasnovski/mini.base16" },
}
