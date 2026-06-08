# locale[]/keymap[] arrays + keyboard config

Status: ready-for-agent

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

- [ ] Schema accepts `system.locale` / `system.keymap` as arrays and
      normalizes a legacy scalar to a single-element array.
- [ ] `identity.sh` uncomments every `locale[]` in `locale.gen` and sets
      `LANG=locale[0]`.
- [ ] `identity.sh` sets vconsole `KEYMAP=keymap[0]`.
- [ ] When a desktop is selected, `identity.sh` writes
      `/etc/X11/xorg.conf.d/00-keyboard.conf` with `XkbLayout=keymap[]`.
- [ ] The Hyprland adapter writes its own `kb_layout` from `keymap[]`.
- [ ] bats: schema accepts array + normalizes scalar; existing identity
      tests green.

## Blocked by

- `.scratch/unified-host-profile/issues/01-profile-loader-schema-assembler.md`
