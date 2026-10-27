# 06: Debuggers — dape

**What to build:** Debugging in Emacs on the same system adapters as
nvim-dap (ADR 0140, ADR 0160): dape (eglot-native; Doom's `:tools debugger`
needs lsp-mode, so it stays off) configured for debugpy, codelldb, dlv and
`js-debug-dap`, with nvim's `SPC d` map — breakpoint, conditional, continue,
step into/over/out, REPL, run last, terminate, UI.

**Blocked by:** 02 (Languages, toolchain, coverage map).

**Status:** done

- [x] `packages.el` adds dape; `:tools debugger` absent
- [x] dape configs use the same adapter binaries nvim-dap uses
- [x] `SPC d*` binds match nvim's
- [x] Static bats: dape declared, debugger module absent, `SPC d` binds
- [x] VM: a Python breakpoint hits and steps; noted in Comments
- [x] Start/continue semantics vs nvim recorded for the ADR

## Comments

- dape at this pin has no codelldb config (only lldb-dap/gdb) and its
  js-debug configs run `node` on a downloaded adapter: both get explicit
  configs on the Fleet Layer binaries (`codelldb --port`, `js-debug-dap
  <port>`), as nvim-dap does. dape's debugpy (`python -m debugpy.adapter`)
  and dlv configs already use system tools.
- `SPC d c` starts a session when none is live, else continues (nvim-dap).
  `SPC d l` maps to `dape-restart` — a loose match for nvim-dap's run_last.
- The emacs bats split at 500 lines: emacs-program.bats (program, pin, hook,
  look, toolchain), emacs-program-parity.bats (keys, theme, org, REST,
  debug), shared emacs-program-helpers.bash.

- VM (arch-niri): a breakpoint on line 2 of a Python file stopped dape
  (debugpy from the system python).
