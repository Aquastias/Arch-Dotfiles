-- mini.nvim modules (ADR 0135): mini.ai (better text objects) + mini.pairs
-- (autopairs). Grouped as one author's modules.
return {
  {
    "echasnovski/mini.ai",
    event = "VeryLazy",
    opts = {},
  },
  {
    "echasnovski/mini.pairs",
    event = "InsertEnter",
    opts = {},
  },
  -- Base16 engine for the Noctalia follow path (ADR 0136); loaded on require by
  -- config/noctalia.lua only when follow_noctalia is on.
  { "echasnovski/mini.base16" },
}
