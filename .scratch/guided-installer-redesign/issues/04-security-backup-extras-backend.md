# Security & Backup Extras back-end

Status: ready-for-agent

## Parent

`.scratch/guided-installer-redesign/PRD.md`

## What to build

Make `post_install.security` / `post_install.backup` real, structured
**Security & Backup Extras** installed via the Primary User's paru pass
(ADR 0041), independent of the guided menu UI (drive it via a committed
Host Profile + VM smoke).

Schema migration (bool → object): `post_install.security` =
`{ firewall: "firewalld"|"ufw"|"none", antivirus: bool, rootkit: bool,
apparmor: bool }`; `post_install.backup` =
`{ zfs_auto_snapshot: bool, borg: bool }`. Update the closed schema, the
schema-table accessors, and the Menu field table; the back-end default stays
**absent = off**.

Resolver (M2): a pure core mapping a `post_install.{security,backup}` object
to the ordered Program-name list (firewall choice → firewalld / ufw /
neither, clamav, rkhunter, apparmor, zfs-auto-snapshot, borg), plus the
secure-baseline default object and shape validation.

Runner (M4): union the resolved Program names into `users[0]`'s paru pass
(the seam host AUR already uses) and dedup against that user's own `programs`
so a tool in both installs once. The selection→install decision is a pure,
unit-tested function; the chroot wiring stays in the Runner. Each tool's
existing Program Install Script runs unchanged in the per-user paru context.

Data: prune `firewalld` / `apparmor` / `clamav` / `rkhunter` from
`users/aquastias/profile.jsonc`; migrate `hosts/vm/arch-secure` and
`hosts/vm/arch-secure-kde-hyprland` from the bool form to the object form;
remove the dead `extras/security.sh` / `extras/backup.sh` dispatch.

## Acceptance criteria

- [ ] Closed schema accepts the object form and rejects the old bool form and
      malformed objects (bad firewall enum, non-bool fields).
- [ ] Resolver maps every firewall × bool combination to the correct Program
      list; the default object = firewalld + clamav + rkhunter + apparmor +
      zfs-auto-snapshot + borg.
- [ ] A tool declared in both `post_install` and `users[0].programs` installs
      once (dedup), order-preserving.
- [ ] aquastias's profile no longer lists the 4 security programs; the two
      `arch-secure*` profiles validate under the object schema.
- [ ] bats for the resolver and the Runner union+dedup function (prior art
      `tests/config/guided-emit.bats`, `tests/profiles/*`).
- [ ] VM smoke: an `arch-secure*` profile installs and the selected daemons
      (firewalld, clamav, rkhunter, apparmor) are enabled in the booted
      system.

## Blocked by

None - can start immediately.
