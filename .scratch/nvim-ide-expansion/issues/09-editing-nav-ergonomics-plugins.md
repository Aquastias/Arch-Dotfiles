# 09 — Editing/nav ergonomics plugins

Status: done
Labels: ready-for-agent

## Parent

`.scratch/nvim-ide-expansion/PRD.md` — Neovim IDE Expansion

## What to build

Add a small bundle of vetted, actively-maintained ergonomics plugins, each
lazy-loaded and each filling a distinct gap:

- **mini.surround** — add/change/delete surrounding quotes/brackets/tags.
- **nvim-ts-autotag** — auto close/rename HTML/JSX/Vue/Svelte tags.
- **nvim-treesitter-context** — pin the current function/class signature at
  the top while scrolling (sticky scroll).
- **flash.nvim** — label-based jump motion for in-buffer navigation.
- **nvim-highlight-colors** — inline colour swatches for hex/rgb/Tailwind.

## Acceptance criteria

- [x] All five plugins are declared and lazy-load on appropriate triggers.
- [ ] Surround edits, tag auto-close/rename, sticky-scroll header, jump motion
      and inline colour swatches each work.
- [x] Seam A asserts each plugin and its lazy trigger.

## Blocked by

None — can start immediately.

## Comments

- 2026-09-27 audit: 348bef4, d26f455. Seam A = tests/config/nvim-program.bats.
  Runtime/Seam B checks not recorded (a 2026-09-27 host run was inconclusive —
  host lacks the program toolchain) — those lines left unticked.
