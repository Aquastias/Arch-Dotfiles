# Action rows always visible (ADR 0063)

Status: done

## Parent

`.scratch/guided-navigation-affordances/PRD.md`

## What to build

Every Guided Installer action row renders as a visible list row again in rich
chrome, exactly as it did on older (legacy-chrome) fzf: `＋ Create user`,
`＋ Add package`, `＋ Add sysctl`, `＋ Add SSH key`, `✗ remove …`, and `← Back`.
The `^A`/`^X`/`Esc` keybindings stay as accelerators. This drops the rich-chrome
gate that hid these rows (`_ctl_action_row` becomes an unconditional emit) and
amends the actions-on-keybindings half of ADR 0047 (recorded as ADR 0063). Rich
chrome otherwise — footer, breadcrumb, borders — is untouched.

The failure this fixes: on modern fzf the only way to add a user was the
undiscoverable `^A` shortcut, because `＋ Create user` was suppressed.

## Acceptance criteria

- [ ] In rich chrome, the Users screen shows a visible `＋ Create user` row.
- [ ] In rich chrome, every screen that has add/remove actions shows them as
      visible rows (`＋ Add package/sysctl/SSH key`, `✗ remove group/pool`), and
      each screen shows a `← Back` row.
- [ ] The `^A`/`^X`/`Esc` keybindings still perform the same actions.
- [ ] Rich-chrome footer/breadcrumb/border behaviour is unchanged.
- [ ] Existing guided bats expectations that asserted "no action rows in rich
      chrome" are updated to the new visible-rows behaviour (prior art:
      `tests/config/guided-chrome.bats`, `guided-users.bats`,
      `guided-profiles-menu.bats`, `guided-packages.bats`), driven headless via
      `guided_ctl_list`.

## Blocked by

- None — can start immediately.
