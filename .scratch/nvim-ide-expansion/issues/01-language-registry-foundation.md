# 01 — Language Registry foundation

Status: ready-for-agent
Labels: ready-for-agent

## Parent

`.scratch/nvim-ide-expansion/PRD.md` — Neovim IDE Expansion (ADR 0141)

## What to build

Introduce the **[[Language Registry]]**: a single table keyed by language that
becomes the source of truth for the per-language toolchain, then refactor the
existing lsp / conform / lint specs to **consume** it instead of carrying their
own inline lists. This is a behaviour-preserving refactor — the same servers,
formatters and linters are wired as today, just from one place. The `dap`
column exists in the row shape but is unused until ticket 02.

Row shape (encodes the decision; data, not behaviour — each consumer still maps
a row into its own plugin shape):

```lua
["<language>"] = {
  lsp        = "<lspconfig server name>",      -- or nil
  treesitter = { "<parser>", ... },
  formatter  = { "<conform formatter>", ... }, -- or nil
  linter     = { "<nvim-lint linter>", ... },  -- or nil
  dap        = "<adapter key>",                -- or nil (ticket 02)
}
```

All current languages are kept; none added or removed.

## Acceptance criteria

- [ ] A single registry table is the source of truth for the per-language
      toolchain; lsp, conform and lint specs derive their config from it.
- [ ] Every language wired today is still wired (no server/formatter/linter
      added or dropped).
- [ ] The row shape includes an (as-yet-unused) `dap` field.
- [ ] Seam A (`nvim-program.bats`) asserts the registry exists and that the
      lsp/conform/lint specs consume it rather than inline lists.
- [ ] Seam B: `:checkhealth` stays green and every in-scope LSP still resolves
      on PATH — no runtime regression from the refactor.

## Blocked by

None — can start immediately.
