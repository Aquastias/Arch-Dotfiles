# 08 — Refactoring commands: refactoring.nvim

Status: ready-for-agent
Labels: ready-for-agent

## Parent

`.scratch/nvim-ide-expansion/PRD.md` — Neovim IDE Expansion

## What to build

Add **refactoring.nvim** for WebStorm-style, treesitter-aware refactors from a
visual selection: extract function, extract variable, extract block, and
inline variable. Lazy-loaded under a `<leader>r` (refactor) group.

## Acceptance criteria

- [ ] refactoring.nvim is declared and lazy-loads (zero startup cost).
- [ ] Extract-function, extract-variable and inline-variable work from a
      selection in a supported language.
- [ ] `<leader>r` keymaps drive the refactors and register a which-key group.
- [ ] Seam A asserts the plugin, its lazy trigger and the maps.

## Blocked by

None — can start immediately.
