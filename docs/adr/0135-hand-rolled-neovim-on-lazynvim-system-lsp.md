# ADR 0135: Hand-rolled Neovim on lazy.nvim; LSP toolchain via system packages

## Status
Accepted — implemented. The served config is the `dev/nvim` User Program's
single-source `home/.config/nvim/` (placed by the Config Apply pass, ADR 0134),
built hand-rolled on lazy.nvim across tickets 01–08. Both prior in-repo configs
— the LazyVim distro at `.config/nvim` and the hand-rolled `.config/nvim.bak` —
are **deleted** (ticket 09), so nothing double-owns `~/.config/nvim` on stow.
Runtime-verified with the Seam-B probe (theme state + live Noctalia follow) and
the `:checkhealth` gate (clean of config defects) against nvim 0.12.5; the
full arch-combined VM parity screenshot is the remaining on-host step (needs
KVM).

## Context
The repo carried two Neovim configs: a LazyVim distro and an older hand-rolled
tree kept as `nvim.bak`. Neither was the deliberate, single served config the
rest of the fleet userland has. Two premises needed grounding first:

- Neovim's built-in plugin manager **`vim.pack` shipped in stable 0.12**
  (2026-03), not 0.13; **0.13 is still nightly**. So "drop LazyVim because the
  new version bundles a manager" conflates two independent axes — the plugin
  **manager** (`vim.pack` vs `lazy.nvim`) and the **framework** (LazyVim distro
  vs hand-rolled).
- `vim.pack` deliberately does **not** reproduce `lazy.nvim`'s declarative
  lazy-loading (`event`/`ft`/`cmd`/`keys`), `opts`, or dependency ordering; its
  maintainer guide frames it for simple configs. For a ~20-language config,
  lazy-loading keeps startup fast without hand-rolled autocmds.

Separately, the fleet already installs LSP servers as **declarative system
packages** (Host Core `packages.language-servers`: rust-analyzer, gopls, zls,
clang, typescript-language-server, yaml-language-server, bash-language-server,
vscode-langservers-extracted; biome under dev). `mason` appears nowhere.

## Decision
Serve **one** hand-rolled Lua Neovim config on **`lazy.nvim`** — not the LazyVim
distro, not `vim.pack` yet — targeting **stable 0.12.x**. Full control fits the
repo's ethos (documented, minimal opaque deps, "reuse before add"); lazy.nvim
keeps a 20-language startup fast and its ecosystem mature. `vim.pack` is
revisited when 0.13 stabilises.

The editor's LSP servers, formatters, and linters install as **system packages**
(repo; AUR only for gaps), arch-wiki-grounded. They are **editor-agnostic dev
tooling**, so they are declared as bare package entries in **Host Core
`packages.language-servers`** beside the existing servers (rust-analyzer, gopls,
zls, …) — the arch-wiki bare-package path — **not** owned by the `dev/nvim`
program. The program owns the config (placed by the Config Apply pass) and the
single genuinely program-shaped exception: **Swift's sourcekit-lsp** (AUR
`swift-bin`, heavy, AUR-only), installed guarded/best-effort in its `install.sh`
so a missing build never fails the install. **No `mason`** — it would duplicate
binaries into nvim's data dir and fight the declarative, reproducible install
the rest of the fleet uses. Nix uses **`nixd`** (versioned AUR); `nil` is
AUR-`git`-only and non-reproducible. `:checkhealth` on the arch-combined VM is
the acceptance gate: zero ERROR, every in-scope LSP on `PATH`, benign WARNs
allowed, unused providers (perl/ruby/node) disabled.

Both prior configs are deleted now the fresh one passes the runtime gate.
