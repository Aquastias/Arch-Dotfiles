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
    -- No image preview; avoids the kitty-graphics checkhealth ERROR headless.
    image = { enabled = false },
  },
  config = function(_, opts)
    require("snacks").setup(opts)
    -- Route vim.ui.select through the picker (snacks checkhealth expects this).
    vim.ui.select = Snacks.picker.select
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
