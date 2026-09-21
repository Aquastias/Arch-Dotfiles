-- Treesitter core. The full language parser set lands with LSP in ticket 02;
-- this tracer bullet ensures the config's own languages highlight.
return {
  "nvim-treesitter/nvim-treesitter",
  branch = "master",
  lazy = false,
  build = ":TSUpdate",
  main = "nvim-treesitter.configs",
  opts = {
    ensure_installed = {
      "lua",
      "vim",
      "vimdoc",
      "bash",
      "markdown",
      "markdown_inline",
      "json",
      "yaml",
      -- Web set (matches the served LSPs) + regex/doc parsers that snacks'
      -- picker and image healthchecks expect, so :checkhealth stays green.
      "regex",
      "css",
      "scss",
      "html",
      "javascript",
      "typescript",
      "tsx",
      "svelte",
      "vue",
      "typst",
      "norg",
    },
    highlight = { enable = true },
    indent = { enable = true },
  },
}
