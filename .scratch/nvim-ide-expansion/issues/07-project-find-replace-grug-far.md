# 07 — Project-wide find & replace: grug-far

Status: ready-for-agent
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

- [ ] grug-far.nvim is declared and lazy-loads on command (zero startup cost).
- [ ] A `<leader>s` keymap opens the find/replace panel with live matches.
- [ ] Applying a replace edits matches across multiple files.
- [ ] Seam A asserts the plugin, its lazy trigger and the map.

## Blocked by

None — can start immediately.
