# 02: Kitty served fleet-wide via a `system/kitty` program

**What to build:** A fresh install — including users created before skel is
seeded, and KDE boxes — comes up with the full [[Kitty Config]] already in the
user's home and a themed default terminal, without the operator having to stow
anything. The same config stays hand-stowable from the repo as the single
source. This is the pi/zsh delivery contract (ADR 0127/0130; installer never
stows, ADR 0095).

**Blocked by:** 01 (seeds the config tree ticket 01 produces).

**Status:** ready-for-agent

- [ ] A new `kind: user` [[User Program]] `system/kitty` seeds the full kitty
      config into the owning user's `$HOME` **and** `/etc/skel`, kept
      byte-identical to the repo stow tree.
- [ ] The program seeds the default generated theme file (Catppuccin Mocha
      Sapphire, ADR 0109) into `$HOME`, `/etc/skel`, and `/root`, so first boot
      and KDE (no template run) have color.
- [ ] The program installs only the Nerd font package; the `kitty` package stays
      owned by core `packages.shell` + the [[Wayland Shell Companion]] preset.
- [ ] The program is registered in User Core `programs` so it reaches the fleet
      like the [[Pi Coding Agent]].
- [ ] A drift test (the zsh/noctalia precedent in `configs.bats`) asserts the
      seeded config equals the repo stow tree byte-for-byte.
- [ ] `noctalia-stow.bats` asserts the program seeds config + default theme and
      installs the font.
