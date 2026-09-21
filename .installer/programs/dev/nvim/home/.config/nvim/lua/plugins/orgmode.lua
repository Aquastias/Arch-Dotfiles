-- orgmode.nvim — Emacs org-mode for Neovim, with real (Emacs-compatible) .org
-- files. It registers and builds its own tree-sitter `org` parser and an `org`
-- LSP, so nvim-treesitter need not add anything. Notes/agenda live under
-- ~/orgfiles (create it to start using capture/agenda).
return {
  "nvim-orgmode/orgmode",
  event = "VeryLazy",
  ft = { "org" },
  config = function()
    require("orgmode").setup({
      org_agenda_files = "~/orgfiles/**/*",
      org_default_notes_file = "~/orgfiles/refile.org",
    })
    -- Org LSP (completion, formatting, some motions) — orgmode registers the
    -- config in setup(); guard so a version without it never errors startup.
    pcall(vim.lsp.enable, "org")
  end,
}
