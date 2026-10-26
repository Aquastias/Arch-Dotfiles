# 03: Keymaps — nvim wins

**What to build:** The nvim `SPC` map drives Emacs (ADR 0160): wherever
Doom binds a key differently, the nvim binding replaces it; Doom keeps every
free key. Covers core (`SPC w/q`, `Tab`/`S-Tab`, `C-h/j/k/l`, `SPC b d`,
`SPC y p`, visual `J`/`K`, `SPC p`, `C-Space`/`BS`), find/search (`SPC f*`,
`SPC s*`, `SPC SPC`, `SPC s r`), git (`SPC g g` lazygit in vterm, magit on
`SPC g m`, hunks, blame, history), diagnostics lists (`SPC x*`), refactor
(`SPC r*` where eglot backs it). Motions: `s` avy (evil-snipe off), `gs*`
surround. Files: `-` dired-jump (wdired), `SPC e` treemacs right. Harpoon on
`SPC a`/`C-e`/`SPC 1..N`, undo tree on `SPC U`, `C-/` terminal, `SPC u h`
inlay hints.

**Blocked by:** 01 (Tracer).

**Status:** ready-for-agent

- [x] `packages.el` adds harpoon and avy; `init.el` enables `undo +tree`,
      treemacs, vterm, magit
- [x] Every nvim bind mirrored where an Emacs command honestly backs it;
      unbacked binds listed for the ADR gaps
- [x] Static bats: the nvim-wins binds and snipe-off present in the config
- [ ] VM: `SPC g g`, `SPC g m`, `s`, `-`, `gsa`/`gsd`/`gsr`, `SPC e`,
      harpoon behave as specified; noted in Comments

## Comments

- Doom prefixes/commands nvim's map displaces (for the ADR): `SPC w`
  (window map; `C-w` remains), `SPC q` (quit map), `SPC u`
  (universal-argument), `SPC x` (scratch), `SPC a` (embark-act; `C-;`
  remains), `SPC RET` (bookmarks), `gs` (easymotion), `]d`/`[d` (hunks →
  now `]h`/`[h`), evil-snipe (disabled).
- Loose matches: nvim's `SPC p` → `evil-kill-on-visual-paste` nil (plain `p`
  keeps the register; Doom's `SPC p` project prefix stays); `SPC r e`/`r v`
  both open eglot's extract action; `SPC r f` opens the code-action menu;
  `SPC g d` diffs unstaged changes (not Diffview's whole-repo view);
  `SPC f h` searches Info manuals; `SPC RET` evaluates the buffer.
- Unmapped (gaps): `cn`/`cN` (a `c`-prefixed normal bind breaks the `c`
  operator), flash's `S`/`r`/`R`/`C-s`, centred `n`/`N`, `J`
  keep-cursor, `SPC g x`, `SPC x q`/`x l`, `SPC -` (oil float).
- vterm builds its module on first use (`vterm-always-compile-module`)
  against the system libvterm; install.sh adds `cmake libvterm` per Doom's
  vterm README (base-devel is in pacstrap).
