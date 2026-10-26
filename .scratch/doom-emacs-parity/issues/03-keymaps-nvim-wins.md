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

- [ ] `packages.el` adds harpoon and avy; `init.el` enables `undo +tree`,
      treemacs, vterm, magit
- [ ] Every nvim bind mirrored where an Emacs command honestly backs it;
      unbacked binds listed for the ADR gaps
- [ ] Static bats: the nvim-wins binds and snipe-off present in the config
- [ ] VM: `SPC g g`, `SPC g m`, `s`, `-`, `gsa`/`gsd`/`gsr`, `SPC e`,
      harpoon behave as specified; noted in Comments

## Comments
