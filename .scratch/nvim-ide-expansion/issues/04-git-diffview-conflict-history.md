# 04 — Git: diffview (conflict resolver + file history)

Status: done
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

- [x] diffview.nvim is declared and lazy-loads on `:Diffview*` (zero startup
      cost).
- [x] `<leader>g` keymaps open the diff/conflict view and file history.
- [x] A `<leader>g` keymap toggles gitsigns inline blame.
- [x] lazygit + gitsigns behaviour is unchanged.
- [x] Seam A asserts the plugin, its lazy trigger and the new maps.

## Blocked by

None — can start immediately.

## Comments

- 2026-09-27 doc sync: shipped in ce255e1, 90b5834, e4d9c5e, 348bef4, d26f455,
  3420c46, 01818f7, aed55a1 (ADR 0140/0141).
