-- snacks.nvim (ADR 0135): picker + dashboard + notifier + the sidebar explorer
-- and git stack (lazygit/gitbrowse). oil owns buffer-style file editing; snacks
-- owns the sidebar tree (replaced neo-tree) and git UI (replaced fugitive).
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
    -- Sidebar file tree (replaced neo-tree). oil keeps netrw, so don't let the
    -- explorer grab it too.
    explorer = { enabled = true, replace_netrw = false },
    -- Quality-of-life modules: nicer vim.ui.input, LSP reference highlight under
    -- cursor, indent-scope, smooth scrolling, and a custom fold/sign/git gutter.
    input = { enabled = true },
    words = { enabled = true },
    scope = { enabled = true },
    scroll = { enabled = true },
    statuscolumn = { enabled = true },
    -- Inline image rendering (files, markdown, PDF, mermaid, LaTeX math) via the
    -- kitty graphics protocol. `svg` is added to formats — snacks rasterizes it
    -- with ImageMagick's rsvg delegate, but it is not a default format. LaTeX
    -- math renders via the `latex` parser (see treesitter.lua) + tectonic.
    image = {
      enabled = true,
      formats = {
        "png", "jpg", "jpeg", "gif", "bmp", "webp", "tiff", "heic", "avif",
        "mp4", "mov", "avi", "mkv", "webm", "pdf", "icns", "svg",
      },
    },
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

    -- Sidebar file explorer (replaced neo-tree's <leader>e).
    map("n", "<leader>e", function()
      Snacks.explorer()
    end, { desc = "Explorer (snacks)" })

    -- Git (replaced fugitive): lazygit for actions, pickers for browsing.
    map("n", "<leader>gg", function()
      Snacks.lazygit()
    end, { desc = "Lazygit" })
    map("n", "<leader>gl", function()
      Snacks.lazygit.log()
    end, { desc = "Lazygit log" })
    map("n", "<leader>gs", function()
      p.git_status()
    end, { desc = "Git status" })
    map("n", "<leader>gb", function()
      p.git_branches()
    end, { desc = "Git branches" })
    map("n", "<leader>gL", function()
      p.git_log()
    end, { desc = "Git log (picker)" })
    map({ "n", "v" }, "<leader>gB", function()
      Snacks.gitbrowse()
    end, { desc = "Git browse (open remote)" })
  end,
}
