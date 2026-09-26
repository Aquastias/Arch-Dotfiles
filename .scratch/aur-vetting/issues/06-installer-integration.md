# 06: Installer integration

**What to build:** guard every installer AUR build path.
- The vetter, its data and a root-owned pin store seeded from the repo are
  staged self-contained into the chroot before the AUR Helper bootstrap and
  installed on every host. It is a core component, not a Program, and not
  toggleable.
- The bootstrap rung calls the vetter between `git clone` and `makepkg`.
- `PreBuildCommand = aur-vet` goes in the system paru.conf and in each
  user's paru.conf dotfile.
- AUR installs refuse to run when the landed AUR Helper is `yay` ("vetting
  needs paru").
- Update the AUR Helper glossary entry and the ADR 0052 cross-reference.

See PRD stories 1-11, 46, 57, 58.

**Blocked by:** 02, 04.

**Status:** done

- [ ] Runner bats: the rung invokes the vetter before `makepkg`; a vetter
      failure fails the rung and falls through the ladder.
- [ ] Runner bats: AUR install with helper `yay` aborts with the refusal
      message; with `paru` it proceeds.
- [ ] A config guard asserts that both paru.conf files carry the hook line.
- [ ] The vetter, data and store are present in the chroot before
      bootstrap (staging bats).
- [ ] The Installer Stdlib is not sourced inside the chroot.
