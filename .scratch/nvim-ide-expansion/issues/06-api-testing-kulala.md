# 06 — In-editor API testing: kulala

Status: ready-for-agent
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

- [ ] kulala.nvim is declared and lazy-loads on the `http` filetype (zero
      startup cost otherwise).
- [ ] Running a request from a `.http` buffer sends it and shows the response.
- [ ] `<leader>R` keymaps drive send/inspect and register a which-key group.
- [ ] Seam A asserts the plugin, its filetype lazy trigger and the maps.

## Blocked by

None — can start immediately.
