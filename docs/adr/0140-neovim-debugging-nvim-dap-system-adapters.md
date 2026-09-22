# ADR 0140: Neovim debugging via nvim-dap; debug adapters as system packages

## Status
Accepted — pending implementation. Extends ADR 0135's no-`mason`,
system-package toolchain to the debug layer. The [[Neovim Config]] roster
gains **nvim-dap** (+ **nvim-dap-ui** and its **nvim-nio** dep) plus the thin
per-language config-wrappers **nvim-dap-python** / **nvim-dap-go**; each
language's adapter is carried by the [[Language Registry]] (ADR 0141).

## Context
The served config (ADR 0135) shipped **no debugging at all** — the one
conspicuous "IDE" gap. The Neovim community's default route to a debugger is
nvim-dap + **mason-nvim-dap**, which downloads adapter binaries into nvim's
data dir. That fights the declarative, reproducible, arch-wiki-grounded
install the fleet already uses for LSP servers, formatters, and linters,
where **`mason` appears nowhere** (ADR 0135). A debug adapter is the same
shape of artifact as an LSP server: an editor-agnostic dev binary on `PATH`.

## Decision
Add **nvim-dap** (+ **nvim-dap-ui**, its **nvim-nio** dep), lazy-loaded on the
`<leader>d` keys. Wire debugging for the **core five** where adapters are
mature: **python** (debugpy), **go** (delve), **rust + c/c++** (codelldb — one
adapter covers all three), **js/ts** (js-debug). The adapter **binaries**
install as **system packages** (repo; AUR only for gaps), arch-wiki-grounded,
declared beside the LSP servers in **Host Core `packages.language-servers`** —
**not `mason-nvim-dap`**, consistent with ADR 0135's no-`mason` rule.
**nvim-dap-python** and **nvim-dap-go** are plugins, not exceptions to that
rule: they only set adapter/config defaults, never install binaries. **PHP**
(xdebug) and **Zig** are deliberately out of scope — xdebug wiring is fiddly
and codelldb's Zig support is immature; either is a one-row [[Language
Registry]] addition later. `:checkhealth dap` (every in-scope adapter
resolvable on `PATH`) joins the acceptance gate.
