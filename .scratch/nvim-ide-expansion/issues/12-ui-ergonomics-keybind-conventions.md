# 12 — UI ergonomics & keybind conventions

Status: ready-for-agent
Labels: ready-for-agent

## Parent

`.scratch/nvim-ide-expansion/PRD.md` — Neovim IDE Expansion

## What to build

Small UI ergonomics plus the hybrid keybind convention:

- **snacks.indent** — enable indent guides (existing snacks module, no new
  plugin).
- **Terminal toggle** — a keymap via snacks.terminal.
- **Buffer delete** — close a buffer without closing its window
  (snacks.bufdelete).
- **`<leader>` group prefixes** — formalise the hybrid convention
  (find `f` / git `g` / code `c` / search `s` / ui `u` / debug `d` /
  diagnostics `x` / refactor `r` / rest `R`) as registered which-key groups so
  the layout is discoverable and consistent across all slices.

## Acceptance criteria

- [ ] Indent guides render; no new plugin added for them.
- [ ] A terminal toggle and a buffer-delete keymap work.
- [ ] which-key shows the full set of `<leader>` group prefixes with the
      agreed convention.
- [ ] Seam A asserts snacks.indent enabled, the terminal/bufdelete maps and
      the which-key group registration.

## Blocked by

None — can start immediately.
