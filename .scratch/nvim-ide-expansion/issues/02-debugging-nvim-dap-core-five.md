# 02 — Debugging via nvim-dap (core-five, system adapters)

Status: done
Labels: ready-for-agent

## Parent

`.scratch/nvim-ide-expansion/PRD.md` — Neovim IDE Expansion (ADR 0140)

## What to build

Add a debugger to the served config. Wire **nvim-dap** with **nvim-dap-ui**
(and its **nvim-nio** dep) plus the thin config-wrappers **nvim-dap-python**
and **nvim-dap-go**, all lazy-loaded under a `<leader>d` group (breakpoints,
step, continue, REPL, UI toggle). Debugging covers the **core five**: python
(debugpy), go (delve), rust + c/c++ (codelldb — one adapter for all three),
js/ts (js-debug). Each language's adapter is declared via the
[[Language Registry]] `dap` column (ticket 01).

Adapter **binaries** install as **system packages** in Host Core
`packages.language-servers` beside the LSP servers, arch-wiki-grounded — **not**
mason-nvim-dap. PHP (xdebug) and Zig are out of scope.

## Acceptance criteria

- [x] nvim-dap + dap-ui (+ nio) + dap-python + dap-go are declared and
      lazy-load (no startup cost when not debugging).
- [x] Debug adapters for python/go/rust/c/c++/js-ts are wired from the
      registry `dap` column; the dap-ui opens on session start.
- [x] `<leader>d` keymaps exist for the core debug actions and register a
      which-key group.
- [x] Host Core declares the adapter packages (codelldb, debugpy, delve,
      js-debug); no mason / mason-nvim-dap anywhere.
- [x] Seam A asserts the plugins, the registry `dap` wiring, the Host Core
      packages and the `<leader>d` maps.
- [ ] Seam B: the adapter binaries resolve on PATH and `:checkhealth dap` is
      clean on the arch-combined VM.

## Blocked by

- `01-language-registry-foundation` (provides the `dap` column).

## Comments

- 2026-09-27 audit: 90b5834, d26f455, aed55a1 (js-debug-dap via
  vscode-js-debug-bin) (ADR 0140). Seam A = tests/config/nvim-program.bats.
  Runtime/Seam B checks not recorded (a 2026-09-27 host run was inconclusive —
  host lacks the program toolchain) — those lines left unticked.
