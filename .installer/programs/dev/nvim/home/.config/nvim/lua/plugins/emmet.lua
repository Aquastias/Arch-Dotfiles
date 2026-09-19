-- nvim-emmet (ADR 0135): wrap/expand Emmet abbreviations (html/css workflow).
-- The emmet-language-server handles completion; this adds the wrap action.
return {
  "olrtg/nvim-emmet",
  keys = {
    {
      "<leader>xe",
      function()
        require("nvim-emmet").wrap_with_abbreviation()
      end,
      mode = { "n", "v" },
      desc = "Emmet wrap with abbreviation",
    },
  },
}
