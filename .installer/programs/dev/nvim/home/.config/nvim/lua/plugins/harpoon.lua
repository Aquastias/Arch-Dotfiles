-- harpoon2 (ADR 0135): pin a handful of files and jump between them. Uses its
-- own quick menu (no telescope dependency in harpoon2).
return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    local harpoon = require("harpoon")
    harpoon:setup()
    local map = vim.keymap.set
    map("n", "<leader>a", function()
      harpoon:list():add()
    end, { desc = "Harpoon add" })
    map("n", "<C-e>", function()
      harpoon.ui:toggle_quick_menu(harpoon:list())
    end, { desc = "Harpoon menu" })
    for i = 1, 4 do
      map("n", "<leader>" .. i, function()
        harpoon:list():select(i)
      end, { desc = "Harpoon " .. i })
    end
  end,
}
