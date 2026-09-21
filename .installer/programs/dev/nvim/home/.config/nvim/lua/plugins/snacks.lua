-- snacks.nvim (ADR 0135): the picker + dashboard + notifier stack, plus a few
-- quality-of-life modules. oil and neo-tree own file exploration, not snacks.
return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    dashboard = { enabled = true },
    picker = { enabled = true },
    notifier = { enabled = true },
    bigfile = { enabled = true },
    quickfile = { enabled = true },
    -- Quality-of-life modules kept green in :checkhealth: nicer vim.ui.input,
    -- LSP reference highlight under cursor, and indent-scope.
    input = { enabled = true },
    words = { enabled = true },
    scope = { enabled = true },
    -- No image preview (oil/neo-tree own files; no image workflow). Snacks still
    -- healthchecks image regardless of this flag, so its WARN is expected.
    image = { enabled = false },
  },
  config = function(_, opts)
    require("snacks").setup(opts)
    -- Route vim.ui.select/input through snacks (checkhealth expects this).
    vim.ui.select = Snacks.picker.select
    vim.ui.input = Snacks.input.input
    local p = Snacks.picker
    local map = vim.keymap.set
    map("n", "<leader><space>", function()
      p.smart()
    end, { desc = "Find files (smart)" })
    map("n", "<leader>ff", function()
      p.files()
    end, { desc = "Find files" })
    map("n", "<leader>fg", function()
      p.grep()
    end, { desc = "Grep" })
    map("n", "<leader>fb", function()
      p.buffers()
    end, { desc = "Buffers" })
    map("n", "<leader>fr", function()
      p.recent()
    end, { desc = "Recent files" })
    map("n", "<leader>fh", function()
      p.help()
    end, { desc = "Help pages" })
  end,
}
