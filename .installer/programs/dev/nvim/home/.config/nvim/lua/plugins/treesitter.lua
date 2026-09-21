-- Treesitter core. The full language parser set lands with LSP in ticket 02;
-- this tracer bullet ensures the config's own languages highlight.
return {
  "nvim-treesitter/nvim-treesitter",
  branch = "master",
  lazy = false,
  build = ":TSUpdate",
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
      "latex",
      "typst",
      "norg",
    },
    highlight = { enable = true },
    indent = { enable = true },
  },
  config = function(_, opts)
    -- tree-sitter CLI 0.26 dropped `generate --no-bindings`, but nvim-treesitter
    -- (master) still passes it — breaking grammars that ship no parser.c and
    -- must be generated (e.g. latex). Set the args ourselves without the removed
    -- flag so those parsers build; then run the normal setup.
    require("nvim-treesitter.install").ts_generate_args =
      { "generate", "--abi", tostring(vim.treesitter.language_version) }
    require("nvim-treesitter.configs").setup(opts)
  end,
}
