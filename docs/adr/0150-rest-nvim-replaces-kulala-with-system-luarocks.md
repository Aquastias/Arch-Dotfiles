# ADR 0150: rest.nvim replaces kulala, with system luarocks

## Status
Accepted — implemented; not yet VM-verified. Replaces kulala.nvim from the
ADR 0135 roster and reverses its `rocks = { enabled = false }` line.

## Context
`mistweaverco/kulala.nvim` went private (GitHub 404, 2026-09-29). There is
no official new home (none in the mistweaverco org, none on Codeberg). The
only copies are small repos from unknown owners, which would be a
supply-chain risk. The `.http` workflow (and the VSCodium rest-client twin,
ADR 0148) still needs a Neovim client.

## Decision
- **rest-nvim/rest.nvim** takes over from kulala. It reads the same JetBrains
  `.http` format, is lazy on `ft = "http"`, and `.rest` maps to `http`. The
  maps stay in the `<leader>R` group: `Rs` run, `Rl` last, `Ro` open, `Re`
  env select, `Rc` curl yank.
- **lazy rocks on, hererocks off:** rest.nvim's deps (nvim-nio, mimetypes,
  xml2lua, fidget.nvim, tree-sitter-http) exist only as rockspec deps.
  `hererocks = false` because hererocks bootstraps through Python.
- **System `luarocks` + `lua51`** (Arch Wiki: Lua → Modules; package-only)
  are installed by the nvim program's `install.sh`, not Host Core, so hosts
  with `packages.inherit: false` get them too.

## Considered Options
- **Pin a kulala copy:** rejected as an unvetted third-party source.
- **Drop in-editor HTTP:** rejected; the operator wants the workflow.
- **Put the deps on the rtp as git plugins:** rejected. mimetypes/xml2lua
  are plain Lua modules, not rtp plugins.

## Consequences
- Adds two repo packages and a rocks tree under `stdpath("data")/lazy-rocks`.
- rest.nvim upstream is slow (last push 2025-12). If it stalls, revisit.
- rest.nvim has no run-all or next/prev-request maps; kulala's
  `Ra`/`Rn`/`Rp`/`Ri` are gone.
- The tree-sitter-http rock and the nvim-treesitter `http` parser both land
  on the rtp. The first one found wins.
