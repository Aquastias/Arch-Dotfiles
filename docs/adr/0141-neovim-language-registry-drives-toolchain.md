# ADR 0141: A single language registry drives the Neovim toolchain plugins

## Status
Accepted — pending implementation. A new registry table
(`lua/config/languages.lua`) becomes the single source consumed by the
lsp / conform / lint / dap specs of [[Neovim Config]]. Paired with ADR 0140,
which supplies the `dap` column.

## Context
The served config wires each language across separate plugin specs — servers
in `lsp.lua`, formatters in `conform.lua`, linters in `lint.lua`, and (per ADR
0140) adapters in a new `dap.lua`. Adding or removing a language means editing
up to four files and keeping them in sync, and the common LazyVim/kickstart
idiom of per-plugin inline lists makes "what is wired for language X"
non-local and prone to drift. A stated goal is to add languages cheaply
("prepared to add more").

## Decision
Introduce a **language registry**: one table keyed by language, each row
declaring `{ lsp, treesitter, formatter, linter, dap }`. The lsp / conform /
lint / dap specs **consume** the registry rather than carrying their own
inline lists, so **adding a language is one table row** and "what is wired for
X" is answered in one place. The accepted trade-off is a layer of indirection
over the plugin-idiomatic separate specs, taken for the single-source-of-truth
and cheap-to-extend properties. The registry is **data, not behaviour**: each
consumer still owns how it turns a row into its plugin's shape (`vim.lsp.enable`,
conform's `formatters_by_ft`, nvim-lint's `linters_by_ft`, dap's
`adapters`/`configurations`). Debug adapters in the `dap` column resolve to
**system-package binaries** (codelldb/debugpy/delve/js-debug), never `mason`
(ADR 0140).
