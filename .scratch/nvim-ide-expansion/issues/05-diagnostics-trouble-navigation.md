# 05 — Diagnostics & navigation: trouble + bracket motions

Status: ready-for-agent
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

- [ ] trouble.nvim is declared and lazy-loads; `<leader>x` opens the
      diagnostics list and the todo list.
- [ ] `]d`/`[d` (diagnostics), `]h`/`[h` (git hunks) and `]t`/`[t` (todos)
      navigation motions are mapped.
- [ ] which-key shows the `<leader>x` group.
- [ ] Seam A asserts the plugin, the `<leader>x` maps and the bracket motions.

## Blocked by

None — can start immediately.
