# 01: Tracer bullet — served config, `dev/nvim` program, sapphire theme

**What to build:** A minimal but end-to-end served [[Neovim Config]]: a
`lazy.nvim` bootstrap with `options`/`keymaps`/`autocmds`, treesitter core, and
a **static Catppuccin Mocha colorscheme with the accent overridden to sapphire**
(`#74c7ec`). Delivered by a new `dev/nvim` [[User Program]] whose single-source
`home/` config tree is placed by the Runner's Config Apply pass (ADR 0134) —
`install.sh` installs the `neovim` runtime dependency only. Opening nvim on a
fresh box lands on the themed editor with a clean core `:checkhealth`. This
slice cuts the whole path (program + config + theme + test) thin.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] `dev/nvim` `config.jsonc` declares a kind=user program; `install.sh` has
      the mandated `set -Eeuo pipefail` + trap shape and no `systemctl start`.
- [ ] Config is single-source under the program's `home/.config/nvim/`; no
      repo-root duplicate is introduced.
- [ ] nvim boots on `lazy.nvim` (not LazyVim, not `vim.pack`) on stable 0.12.x.
- [ ] Default look is Catppuccin Mocha with a sapphire accent; `termguicolors`
      on; unused providers (perl/ruby/node) disabled so they do not warn.
- [ ] `nvim-program.bats` skeleton asserts the program shape and single-source
      config, cloned from `kitty-program.bats`/`pi-agent.bats`.
- [ ] Core `:checkhealth` (nvim, treesitter) reports zero ERROR.
