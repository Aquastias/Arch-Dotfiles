# 05 — Diagnostics & navigation: trouble + bracket motions

Status: done
Labels: ready-for-agent

## Parent

`.scratch/nvim-ide-expansion/PRD.md` — Neovim IDE Expansion

## What to build

Add **trouble.nvim**, lazy-loaded, for a project-wide diagnostics/quickfix
list and a todo-comments list (via the existing todo-comments integration),
under a `<leader>x` group. Add `]`/`[` navigation motions for diagnostics,
git hunks (gitsigns) and todo comments so they can be traversed without
commands.

## Acceptance criteria

- [x] trouble.nvim is declared and lazy-loads; `<leader>x` opens the
      diagnostics list and the todo list.
- [x] `]d`/`[d` (diagnostics), `]h`/`[h` (git hunks) and `]t`/`[t` (todos)
      navigation motions are mapped.
- [x] which-key shows the `<leader>x` group.
- [x] Seam A asserts the plugin, the `<leader>x` maps and the bracket motions.

## Blocked by

None — can start immediately.

## Comments

- 2026-09-27 audit: 348bef4, d26f455. Seam A = tests/config/nvim-program.bats.
  Runtime/Seam B checks not recorded (a 2026-09-27 host run was inconclusive —
  host lacks the program toolchain) — those lines left unticked.
