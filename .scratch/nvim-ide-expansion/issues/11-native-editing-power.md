# 11 — Native editing power & structural selection

Status: done
Labels: ready-for-agent

## Parent

`.scratch/nvim-ide-expansion/PRD.md` — Neovim IDE Expansion

## What to build

Deliver the VS Code multi-edit and structural-selection workflows without new
plugins:

- **Native multi-cursor** — `cn` (`*``cgn`) and `cN` (`#``cgN`) to change the
  word under the cursor and repeat with `.`, a visual variant to change a
  selection everywhere, alongside native visual-block (`<C-v>` `I`/`A`/`c`).
- **Function/class text objects** — wire mini.ai with treesitter so `af`/`ac`
  select whole function/class definitions.
- **Incremental selection** — expand/shrink a selection by syntax node
  (WebStorm's Ctrl+W).
- **Context-aware commenting** — `gc` lands correctly in embedded regions for
  JSX/Vue/Svelte.

## Acceptance criteria

- [x] `cn`/`cN` + `.` change repeated words; the visual variant changes a
      selection's occurrences; visual-block editing works.
- [x] `af`/`ac` operate on function/class definitions via mini.ai + treesitter.
- [x] Incremental selection grows/shrinks by syntax node.
- [x] `gc` comments correctly in JSX/Vue/Svelte embedded regions.
- [x] No multi-cursor plugin is added.
- [x] Seam A asserts the multi-cursor maps, the mini.ai treesitter wiring, the
      incremental-selection maps and the context-comment setup.

## Blocked by

None — can start immediately.

## Comments

- 2026-09-27 doc sync: shipped in ce255e1, 90b5834, e4d9c5e, 348bef4, d26f455,
  3420c46, 01818f7, aed55a1 (ADR 0140/0141).
