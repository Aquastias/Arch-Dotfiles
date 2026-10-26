# 06: Debuggers — dape

**What to build:** Debugging in Emacs on the same system adapters as
nvim-dap (ADR 0140, ADR 0160): dape (eglot-native; Doom's `:tools debugger`
needs lsp-mode, so it stays off) configured for debugpy, codelldb, dlv and
`js-debug-dap`, with nvim's `SPC d` map — breakpoint, conditional, continue,
step into/over/out, REPL, run last, terminate, UI.

**Blocked by:** 02 (Languages, toolchain, coverage map).

**Status:** ready-for-agent

- [ ] `packages.el` adds dape; `:tools debugger` absent
- [ ] dape configs use the same adapter binaries nvim-dap uses
- [ ] `SPC d*` binds match nvim's
- [ ] Static bats: dape declared, debugger module absent, `SPC d` binds
- [ ] VM: a Python breakpoint hits and steps; noted in Comments
- [ ] Start/continue semantics vs nvim recorded for the ADR

## Comments
