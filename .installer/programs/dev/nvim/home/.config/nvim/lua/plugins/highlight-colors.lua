-- nvim-highlight-colors: inline swatches for #rrggbb / rgb() / Tailwind classes,
-- useful for the CSS/Tailwind/Svelte/Vue work. Lazy on read.
return {
  "brenoprata10/nvim-highlight-colors",
  event = { "BufReadPost", "BufNewFile" },
  opts = {
    render = "background",
    enable_tailwind = true,
  },
}
