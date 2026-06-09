# locale[]/keymap[] arrays + keyboard config

Status: done

## Parent

`.scratch/unified-host-profile/PRD.md`

## What to build

Make `system.locale` and `system.keymap` arrays whose first element is
the default. The schema normalizes a legacy scalar to a single-element
array so legacy synthesis keeps validating (green-throughout). At install
time `identity.sh` generates every listed locale, sets `LANG`/console
`KEYMAP` from element 0, and — when a desktop is selected — writes the
shared X11 keyboard config from the full layout list. The Hyprland
adapter writes its own `kb_layout` (it ignores `xorg.conf.d`).

## Acceptance criteria

- [x] Schema accepts `system.locale` / `system.keymap` as arrays and
      normalizes a legacy scalar to a single-element array.
- [x] `identity.sh` uncomments every `locale[]` in `locale.gen` and sets
      `LANG=locale[0]`.
- [x] `identity.sh` sets vconsole `KEYMAP=keymap[0]`.
- [x] When a desktop is selected, `identity.sh` writes
      `/etc/X11/xorg.conf.d/00-keyboard.conf` with `XkbLayout=keymap[]`.
- [ ] The Hyprland adapter writes its own `kb_layout` from `keymap[]`.
      *Deferred → VM-verified phase: no `hyprland.conf` seam exists in the
      repo (it comes from the operator's `dotfiles_repo`), arrays don't
      `export` to the adapter subprocess, and the effect is unverifiable
      without a VM. Goes with the hyprland VM smoke (`vm-profile-harness
      /07`).*
- [x] bats: schema accepts array + normalizes scalar; existing identity
      tests green.

## Blocked by

- `.scratch/unified-host-profile/issues/01-profile-loader-schema-assembler.md`

## Comments

Data layer done via TDD (the kernel-selection pattern applied to
locale/keymap): schema accepts `system.locale[]`/`system.keymap[]` and a
scalar still validates (the `[]` pattern admits both); accessors
`install_config_locales`/`install_config_keymaps` emit the list (primary
first, defaults `en_US.UTF-8`/`us`), with `install_config_locale`/`keymap`
returning the primary; install-state carries `LOCALES`/`KEYMAPS` arrays
alongside the scalar primaries (round-trip green). `identity.sh` now
generates every locale, keeps `LANG`/`KEYMAP` from element 0, and writes
the shared X11 keyboard config from the full keymap list when a desktop is
selected.

Tests: +2 profile-loader (schema array/scalar), +8 install-config
(locale/keymap accessors), +4 install-state (LOCALES/KEYMAPS load + write);
fixtures in chroot-initcpio + environment-runner updated for the new
required wire fields. Full suite green (1012).

Carve-out: criterion #5 (Hyprland `kb_layout`) deferred to the VM-verified
phase — see the unchecked box above.
