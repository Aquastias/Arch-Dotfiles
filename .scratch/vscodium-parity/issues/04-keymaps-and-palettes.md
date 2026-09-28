# 04: Keymaps + palettes

**What to build:** Key parity with the [[Neovim Config]] via VSCodeVim wherever
a VSCodium command honestly backs the nvim map (ADR 0148): find/search
(`<leader><space>`, `ff/fg/fb/fr`, `ss/sS/sc/sk`, `sr`), LSP (`grn/gra/grr/gri/
grd`, `K`, `<leader>co`), jumps (`]d/[d`, `]h/[h`, `]t/[t`), trouble
(`<leader>xx/xX/xt`), git (`<leader>gg` lazygit in terminal, `gd/gh/gt`),
explorer (`-` reveal, `<leader>e`), buffers/windows (`<Tab>/<S-Tab>`,
`<leader>bd`, `<C-h/j/k/l>`, `<C-/>`), basics (`<leader>w/q`), UI (`uh`, `uC`),
REST (`<leader>R*`), refactor (`<leader>r*` via code actions), folds (`zR/zM`).
`vim.sneak` on `s`/`S`, easymotion off; `gsa/gsd/gsr` remapped onto VSCodeVim
surround. Native chords go in the keybindings file. The rose-pine, tokyonight,
gruvbox and nord theme extensions join the list so `<leader>uC` picks among the
five nvim palettes.

**Blocked by:** 02 (Tracer).

**Status:** done

- [x] Static bats: sneak on, easymotion off, surround on, leader Space; the
      five palettes' extension IDs listed; each mapped leader key present
- [x] The four extra palettes confirmed on Open VSX (drop + note in ADR 0148
      if one is missing)
- [x] VM: `gs*` surround remap works — else fall back to `ys/ds/cs` and
      record the difference in ADR 0148
- [x] VM: spot-check `<leader>ff`, `<leader>gg`, `<leader>uC`, `-`

## Comments

- Static slice done; all four palettes on Open VSX. Command IDs checked
  against the vscodium-bin 1.135 workbench (read-only). Unmapped keys listed
  in ADR 0148. Surround + spot-checks run in ticket 06 (VM).
