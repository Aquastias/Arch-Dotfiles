# 08 — Refactoring commands: refactoring.nvim

Status: done
Labels: ready-for-agent

## Parent

`.scratch/nvim-ide-expansion/PRD.md` — Neovim IDE Expansion

## What to build

Add **refactoring.nvim** for WebStorm-style, treesitter-aware refactors from a
visual selection: extract function, extract variable, extract block, and
inline variable. Lazy-loaded under a `<leader>r` (refactor) group.

## Acceptance criteria

- [x] refactoring.nvim is declared and lazy-loads (zero startup cost).
- [x] Extract-function, extract-variable and inline-variable work from a
      selection in a supported language.
- [x] `<leader>r` keymaps drive the refactors and register a which-key group.
- [x] Seam A asserts the plugin, its lazy trigger and the maps.

## Blocked by

None — can start immediately.

## Comments

- 2026-09-27 doc sync: shipped in ce255e1, 90b5834, e4d9c5e, 348bef4, d26f455,
  3420c46, 01818f7, aed55a1 (ADR 0140/0141).
