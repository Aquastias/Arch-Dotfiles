# 03 — Roster accuracy: drop nvim-emmet, Emmet via LSP

Status: ready-for-agent
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

- [ ] `nvim-emmet` and its keymap are removed from the config.
- [ ] Emmet still works via `emmet_language_server` (LSP present and enabled).
- [ ] Seam A no longer asserts `nvim-emmet`, `neo-tree` or `fugitive`, and the
      roster assertions reflect the actual served plugins.
- [ ] Seam B: `:checkhealth` stays green.

## Blocked by

None — can start immediately.
