# 03 — Roster accuracy: drop nvim-emmet, Emmet via LSP

Status: done
Labels: ready-for-agent

## Parent

`.scratch/nvim-ide-expansion/PRD.md` — Neovim IDE Expansion

## What to build

Remove the abandoned, single-maintainer `nvim-emmet` plugin and its keymap.
Emmet expansion is served by the already-installed `emmet_language_server`
LSP, so there is no feature loss. Correct the now-inaccurate static-seam
assertions in `nvim-program.bats` that still reference retired plugins
(`neo-tree`, `fugitive`, `nvim-emmet`) so the seam matches the real roster.

## Acceptance criteria

- [x] `nvim-emmet` and its keymap are removed from the config.
- [x] Emmet still works via `emmet_language_server` (LSP present and enabled).
- [x] Seam A no longer asserts `nvim-emmet`, `neo-tree` or `fugitive`, and the
      roster assertions reflect the actual served plugins.
- [x] Seam B: `:checkhealth` stays green.

## Blocked by

None — can start immediately.

## Comments

- 2026-09-27 doc sync: shipped in ce255e1, 90b5834, e4d9c5e, 348bef4, d26f455,
  3420c46, 01818f7, aed55a1 (ADR 0140/0141).
