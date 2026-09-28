# 02: Tracer — `dev/vscodium` program, look, VM smoke

**What to build:** A minimal end-to-end [[VSCodium Config]] (ADR 0148): an
opt-in `dev/vscodium` [[User Program]] installs `vscodium-bin` and, per owning
user, the extensions in the program's extension data file (Open VSX, unpinned,
additive only) — seeded here with VSCodeVim and the catppuccin theme + icons.
Settings/keybindings live in the program's `home/` and arrive via Config Apply
(user + `/etc/skel`). Look: Catppuccin Mocha, sapphire accent, no black
overrides, `catppuccin-mocha` icons, FiraCode Nerd Font 12 + ligatures (editor
and terminal), sidebar right, no startup editor, sticky scroll; VSCodeVim basics
(Space leader, `jj`, relative numbers, system clipboard, `<C-a/f/p>` passed
through). vscodium joins the stow opt-in set.

**Blocked by:** 01 (Stow opt-in).

**Status:** ready-for-agent

- [ ] Program metadata (`kind: user`) + install.sh with mandated shape; not in
      User Core; install.sh does not seed `home/`
- [ ] Extension data file (one ID per line, comments allowed) drives
      `codium --install-extension`; never uninstalls
- [ ] New static bats: program shape, settings/keybindings parse (JSONC
      helper), look values, no MS Marketplace reference in the program
- [ ] vscodium in the stow opt-in set; `./stow-configs.sh` (no args) skips it
- [ ] VM (vm-agent): install with vscodium selected; `--list-extensions`
      matches; themed screenshot; result noted in Comments
- [ ] Host VSCodium untouched
