-- orgmode.nvim — Emacs-compatible .org files. Builds its own tree-sitter `org`
-- parser + `org` LSP, so nvim-treesitter adds nothing. Notes/agenda live under
-- ~/orgfiles (create it to use capture/agenda).
return {
  "nvim-orgmode/orgmode",
  event = "VeryLazy",
  ft = { "org" },
  config = function()
    require("orgmode").setup({
      org_agenda_files = "~/orgfiles/**/*",
      org_default_notes_file = "~/orgfiles/refile.org",
    })
    -- Org LSP; pcall-guarded so a version lacking it never errors startup.
    pcall(vim.lsp.enable, "org")
  end,
}
