# 02 — Debugging via nvim-dap (core-five, system adapters)

Status: ready-for-agent
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

- [ ] nvim-dap + dap-ui (+ nio) + dap-python + dap-go are declared and
      lazy-load (no startup cost when not debugging).
- [ ] Debug adapters for python/go/rust/c/c++/js-ts are wired from the
      registry `dap` column; the dap-ui opens on session start.
- [ ] `<leader>d` keymaps exist for the core debug actions and register a
      which-key group.
- [ ] Host Core declares the adapter packages (codelldb, debugpy, delve,
      js-debug); no mason / mason-nvim-dap anywhere.
- [ ] Seam A asserts the plugins, the registry `dap` wiring, the Host Core
      packages and the `<leader>d` maps.
- [ ] Seam B: the adapter binaries resolve on PATH and `:checkhealth dap` is
      clean on the arch-combined VM.

## Blocked by

- `01-language-registry-foundation` (provides the `dap` column).
