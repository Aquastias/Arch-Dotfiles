-- nvim-ts-autotag: auto close + rename HTML/JSX/Vue/Svelte tags via treesitter.
-- Lazy on the markup filetypes.
return {
  "windwp/nvim-ts-autotag",
  ft = {
    "html",
    "xml",
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
    "svelte",
    "vue",
    "markdown",
    "php",
  },
  opts = {},
}
