# 13 — Folding tune: ufo provider chain + fold gutter

Status: ready-for-agent
Labels: ready-for-agent

## Parent

`.scratch/nvim-ide-expansion/PRD.md` — Neovim IDE Expansion

## What to build

Tune the existing **nvim-ufo** folding to feel IDE-grade: provider chain
LSP → treesitter → indent; files open fully unfolded (`foldlevel=99`); a
readable foldtext (first line + `⋯ N lines`); `zK` to peek a closed fold; keep
`zR`/`zM` and add incremental `zr`/`zm`. Turn on a minimal **fold gutter**
(`foldcolumn=1`) with nerd-font `▶`/`▼` markers.

## Acceptance criteria

- [ ] Files open unfolded; folds come from LSP, then treesitter, then indent.
- [ ] Fold summary shows the first line + line count; `zK` peeks a fold;
      `zr`/`zm` fold incrementally alongside `zR`/`zM`.
- [ ] A `foldcolumn=1` gutter shows clickable `▶`/`▼` markers.
- [ ] Seam A asserts the ufo provider/foldlevel/foldtext config and the
      foldcolumn setting.

## Blocked by

None — can start immediately.
