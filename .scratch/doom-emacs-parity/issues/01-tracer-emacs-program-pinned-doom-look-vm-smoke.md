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

**Status:** done

- [x] Program metadata (`kind: user`, `stow_opt_in`) + install.sh with the
      mandated shape; not in User Core or Host Core; install.sh does not seed
      `home/`
- [x] Pin data file holds one 40-hex commit; install.sh checks it out; a
      re-run fetches and re-pins an existing clone, never deletes it
- [x] `emacs` appended to the operator's `programs` after `vscodium`;
      desktop, laptop and VM fixture goldens updated
- [x] New static bats (prior art: vscodium program test): program shape, pin
      format, minimal `init.el`/`packages.el`/`config.el` look values
- [x] `./stow-configs.sh` (no args) skips emacs; named, it stows
- [x] VM (vm-agent, `arch-combined`): install with emacs selected; Emacs
      launches with Doom loaded and themed; screenshot noted in Comments
- [x] Lints (readability, no-python) pass

## Comments

- Doom bakes its config dir's absolute path into its generated profile, and
  Config Apply runs after every install.sh, so the sync cannot run in
  install.sh. Operator chose a generic **Post-Config Hook**: a user program
  may ship `post-config.sh`, run as its user after Config Apply (runner +
  bats + PROGRAM_SPEC; ADR 0134 amended, ADR 0160 updated).
- Doom's canonical repo is `doomemacs/core`; its modules are a submodule
  (`doomemacs/modules`) pinned by the core commit's gitlink.
- Pinned clone verified locally against GitHub (fresh clone + re-run re-pin).
- VM smoke deferred to one batched VM pass after tickets 02–07 (each
  ticket's VM criterion recorded there).

- VM (2026-10-27): fresh `arch-kde` install from local HEAD ca57273 —
  emacs-wayland/cmake/libvterm installed, Doom at the pin, config placed,
  Doom's profile generated after it (the Post-Config Hook ran). `arch-niri`
  replay: `doom install` rc 0. Themed screenshots taken (Catppuccin +
  sapphire). VM found two fixes: autoloads for bound commands, snippets dir.
