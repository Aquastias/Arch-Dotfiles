# 01: Tracer — `dev/emacs` program, pinned Doom, look, VM smoke

**What to build:** A minimal end-to-end [[Emacs Config]] (ADR 0160): an
opt-in `dev/emacs` [[User Program]] in the operator's User Profile installs
the Wayland Emacs build, clones Doom into the owning user's Emacs dir at the
commit in the program's pin data file, and runs Doom's install/sync
non-interactively (a failed sync warns, never fails the install). A minimal
Doom user config arrives via Config Apply (user + `/etc/skel`): evil, `SPC`
leader, which-key, FiraCode Nerd Font 12 + ligatures, nerd-icons, static
Catppuccin Mocha + sapphire. emacs joins the stow opt-in set via program
metadata. Ground every package on the Arch Wiki.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] Program metadata (`kind: user`, `stow_opt_in`) + install.sh with the
      mandated shape; not in User Core or Host Core; install.sh does not seed
      `home/`
- [ ] Pin data file holds one 40-hex commit; install.sh checks it out; a
      re-run fetches and re-pins an existing clone, never deletes it
- [ ] `emacs` appended to the operator's `programs` after `vscodium`;
      desktop, laptop and VM fixture goldens updated
- [ ] New static bats (prior art: vscodium program test): program shape, pin
      format, minimal `init.el`/`packages.el`/`config.el` look values
- [ ] `./stow-configs.sh` (no args) skips emacs; named, it stows
- [ ] VM (vm-agent, `arch-combined`): install with emacs selected; Emacs
      launches with Doom loaded and themed; screenshot noted in Comments
- [ ] Lints (readability, no-python) pass

## Comments
