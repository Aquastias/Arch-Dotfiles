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
- [ ] Extract-function, extract-variable and inline-variable work from a
      selection in a supported language.
- [x] `<leader>r` keymaps drive the refactors and register a which-key group.
- [x] Seam A asserts the plugin, its lazy trigger and the maps.

## Blocked by

None — can start immediately.

## Comments

- 2026-09-27 audit: 348bef4, d26f455, 01818f7 (select_refactor dropped). Seam A
  = tests/config/nvim-program.bats. Runtime/Seam B checks not recorded (a
  2026-09-27 host run was inconclusive — host lacks the program toolchain) —
  those lines left unticked.
