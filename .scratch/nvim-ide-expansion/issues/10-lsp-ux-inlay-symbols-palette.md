# 10 — LSP UX: inlay hints, signature help, symbols, palette

Status: done
Labels: ready-for-agent

## Parent

`.scratch/nvim-ide-expansion/PRD.md` — Neovim IDE Expansion

## What to build

Close the VS Code / WebStorm LSP-UX gaps using native or existing plugins (no
new dependencies):

- **Inlay hints** — native `vim.lsp.inlay_hint`, default **on**, toggle
  `<leader>uh`.
- **Signature help** — enabled in blink.cmp (parameter popup while typing).
- **Document + workspace symbol pickers** — via snacks (`<leader>ss` /
  `<leader>sS`); the "go to symbol in file / workspace" workflow.
- **Command palette** — snacks commands/keymaps picker (`<leader>sc`).
- **Organise imports** — an LSP source action (`<leader>co`).

## Acceptance criteria

- [ ] Inlay hints show by default and toggle off/on with `<leader>uh`.
- [ ] blink.cmp shows signature help while typing a call.
- [x] Document and workspace symbol pickers and a command palette are mapped.
- [x] An organise-imports action is mapped and runs via the LSP.
- [x] No new plugins are added for any of the above.
- [ ] Seam A asserts the inlay-hint default + toggle and the new maps; Seam B
      (probe) may assert inlay hints default on.

## Blocked by

None — can start immediately.

## Comments

- 2026-09-27 audit: 348bef4, d26f455. Seam A = tests/config/nvim-program.bats.
  Runtime/Seam B checks not recorded (a 2026-09-27 host run was inconclusive —
  host lacks the program toolchain) — those lines left unticked.
