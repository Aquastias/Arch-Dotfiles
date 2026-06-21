# Security & Backup menu categories + no-user guard

Status: ready-for-agent

## Parent

`.scratch/guided-installer-redesign/PRD.md`

## What to build

Wire the **Security** and **Backup** Configuration Categories into the
two-level menu so the operator chooses what installs, authoring the
structured `post_install.{security,backup}` objects the back-end consumes.

Security category: a firewall radiolist (firewalld / ufw / none — single
choice; firewalld and ufw are mutually exclusive), plus toggles for antivirus
(clamav), rootkit (rkhunter) and apparmor. Backup category: toggles for
zfs-auto-snapshot and borg. A fresh guided run pre-ticks firewalld + clamav +
rkhunter + apparmor and zfs-auto-snapshot + borg (the secure baseline from
the resolver default).

Terminal-action guard (M5): when `post_install.security` or
`post_install.backup` resolves to a non-empty Program list but the host has
no users, the terminal action (Proceed / Save / Export) aborts with an
actionable message ("security/backup install via paru and need a primary
user — add a user or clear the selections").

## Acceptance criteria

- [ ] Security / Backup are top-level categories; drilling in shows the
      firewall radiolist + tool toggles.
- [ ] The firewall is single-choice; the choice + toggles emit a valid
      structured `post_install.security` / `post_install.backup` object.
- [ ] A fresh guided run pre-ticks firewalld + clamav + rkhunter + apparmor
      and zfs-auto-snapshot + borg.
- [ ] With selections set and zero users, Proceed / Save / Export abort with
      the actionable message; with a user, or with empty selections, they
      pass.
- [ ] bats for the no-user guard (prior art `tests/config/validation-*.bats`)
      and stubbed-fzf bats for the Security / Backup editors.
- [ ] VM smoke (guided replay): driving the Security / Backup categories
      installs the selected daemons in the booted system.

## Blocked by

- `.scratch/guided-installer-redesign/issues/02-two-level-category-menu.md`
- `.scratch/guided-installer-redesign/issues/04-security-backup-extras-backend.md`
