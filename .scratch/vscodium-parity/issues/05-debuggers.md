# 05: Debuggers

**What to build:** Debugging for every nvim dap target (ADR 0140/0148): Python
(debugpy extension, bundled), Go (golang.go using the system `dlv`), Rust/C/C++
(codelldb extension; adapter downloaded on first debug — accepted exception),
JS/TS (built-in js-debug). Debug keys match nvim: `<leader>db/dB/dc/di/do/dO/
dr/dl/dt/du`.

**Blocked by:** 03 (Languages), 04 (Keymaps).

**Status:** ready-for-agent

- [x] Debug extensions in the list; Coverage Map entries updated where the
      debugger is part of a language's coverage
- [x] Static bats: `<leader>d*` bindings present; go dlv path is the system one
- [ ] VM: a breakpoint hit in at least one language (Python or Go); note
      whether codelldb's first-run download succeeds

## Comments

- Static slice done. `dc` continues only; `dl` starts (ADR 0148 Behaviour
  differences). python.languageServer None avoids a 2nd server beside
  basedpyright. Breakpoint check runs in ticket 06 (VM).
