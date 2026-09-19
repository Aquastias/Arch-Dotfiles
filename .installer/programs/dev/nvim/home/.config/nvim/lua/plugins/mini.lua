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
}
