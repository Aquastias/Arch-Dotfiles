# Root row merge → Root Editor

Status: done

## Parent

`.scratch/guided-navigation-affordances/PRD.md`

## What to build

Collapse root's two Users-screen rows (`root password` and `root shell`) into a
single `root — <shell> · pw <tag>` row, symmetric with a normal user row. Enter
on it opens a **Root Editor** sub-screen exposing exactly `password` and `shell`
(root has no groups/sudo/programs). The password uses the inline-masked,
type-twice-confirm capture and the no-SOPS manifest's root role; `shell` cycles
`/bin/bash → /bin/zsh → /bin/fish`. Storage is unchanged — `options.root_shell`
(normalised out at the default) and the root password manifest role — only the
menu surface changes: every account row now opens its own editor.

## Acceptance criteria

- [ ] The Users screen shows one `root — <shell> · pw <tag>` row and no longer
      shows the separate `root password` / `root shell` rows.
- [ ] Enter on the root row navigates to a Root Editor screen with a `password`
      row and a `shell` row (and a Back affordance).
- [ ] Setting the root password from the Root Editor stores it under the root
      role in the no-SOPS manifest, masked and confirmed as the other password
      fields are.
- [ ] Cycling the shell stores `options.root_shell`, normalised
      out when equal to the default — identical to today's stored value.
- [ ] The root password/shell defaults and their tags (`default 12345`, shell
      basename) render on the merged row.
- [ ] Covered via `guided_ctl_list` (merged row present, old rows absent)
      and `guided_ctl_enter` (root row opens the Root Editor); prior art:
      `tests/config/guided-users.bats`, `guided-shell.bats`.

## Blocked by

- None — can start immediately.
