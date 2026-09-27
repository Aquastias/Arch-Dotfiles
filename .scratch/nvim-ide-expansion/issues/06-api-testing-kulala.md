# 06 — In-editor API testing: kulala

Status: done
Labels: ready-for-agent

## Parent

`.scratch/nvim-ide-expansion/PRD.md` — Neovim IDE Expansion

## What to build

Add **kulala.nvim** for running HTTP requests from `.http`/`.rest` files
(VS Code REST Client / IntelliJ HTTP Client syntax) inside the editor, so API
tests live next to the code and are committable. Pure Lua, no external deps;
lazy-loads on the `http` filetype. Register the `http` parser with treesitter
(via the registry where appropriate). Keymaps under a new `<leader>R` group.

## Acceptance criteria

- [x] kulala.nvim is declared and lazy-loads on the `http` filetype (zero
      startup cost otherwise).
- [x] Running a request from a `.http` buffer sends it and shows the response.
- [x] `<leader>R` keymaps drive send/inspect and register a which-key group.
- [x] Seam A asserts the plugin, its filetype lazy trigger and the maps.

## Blocked by

None — can start immediately.

## Comments

- 2026-09-27 doc sync: shipped in ce255e1, 90b5834, e4d9c5e, 348bef4, d26f455,
  3420c46, 01818f7, aed55a1 (ADR 0140/0141).
