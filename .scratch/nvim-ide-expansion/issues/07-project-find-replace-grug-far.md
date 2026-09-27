# 07 — Project-wide find & replace: grug-far

Status: done
Labels: ready-for-agent

## Parent

`.scratch/nvim-ide-expansion/PRD.md` — Neovim IDE Expansion

## What to build

Add **grug-far.nvim** for a VS Code-style search/replace panel: type a search
and replacement, see live matches across the whole repo (ripgrep-backed),
tune include/exclude globs, and apply. Complements snacks' grep (which finds
but does not replace across files). Lazy-loads on command; keymaps under the
`<leader>s` (search) group.

## Acceptance criteria

- [x] grug-far.nvim is declared and lazy-loads on command (zero startup cost).
- [x] A `<leader>s` keymap opens the find/replace panel with live matches.
- [x] Applying a replace edits matches across multiple files.
- [x] Seam A asserts the plugin, its lazy trigger and the map.

## Blocked by

None — can start immediately.

## Comments

- 2026-09-27 doc sync: shipped in ce255e1, 90b5834, e4d9c5e, 348bef4, d26f455,
  3420c46, 01818f7, aed55a1 (ADR 0140/0141).
