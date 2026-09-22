-- which-key (ADR 0135): the leader popup of available keybindings. The group
-- prefixes formalise the hybrid LazyVim-convention layout (ADR: keybind base).
return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  opts = {
    spec = {
      { "<leader>b", group = "buffer" },
      { "<leader>c", group = "code" },
      { "<leader>d", group = "debug" },
      { "<leader>f", group = "find" },
      { "<leader>g", group = "git" },
      { "<leader>r", group = "refactor" },
      { "<leader>R", group = "REST" },
      { "<leader>s", group = "search" },
      { "<leader>u", group = "ui/toggle" },
      { "<leader>x", group = "diagnostics" },
    },
  },
}
