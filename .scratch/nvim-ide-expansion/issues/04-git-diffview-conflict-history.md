# 04 — Git: diffview (conflict resolver + file history)

Status: ready-for-agent
Labels: ready-for-agent

## Parent

`.scratch/nvim-ide-expansion/PRD.md` — Neovim IDE Expansion

## What to build

Add **diffview.nvim**, lazy-loaded on its `:Diffview*` commands, scoped to two
jobs lazygit is worse at: side-by-side **merge-conflict resolution** and a
navigable **file/branch history** diff view with real syntax highlighting.
lazygit stays the daily git driver and gitsigns is unchanged. Add a
toggle for inline git blame (gitsigns). Keymaps live under the `<leader>g`
group.

## Acceptance criteria

- [ ] diffview.nvim is declared and lazy-loads on `:Diffview*` (zero startup
      cost).
- [ ] `<leader>g` keymaps open the diff/conflict view and file history.
- [ ] A `<leader>g` keymap toggles gitsigns inline blame.
- [ ] lazygit + gitsigns behaviour is unchanged.
- [ ] Seam A asserts the plugin, its lazy trigger and the new maps.

## Blocked by

None — can start immediately.
