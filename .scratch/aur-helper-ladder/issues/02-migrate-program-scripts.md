# Migrate the 14 program `install.sh` scripts to `${AUR_HELPER}`

Status: done

## Parent

`.scratch/aur-helper-ladder/PRD.md` — Resilient AUR-helper bootstrap ladder
(ADR 0052).

## What to build

Every `programs/*/install.sh` calls `${AUR_HELPER} -S` instead of the literal
`paru`, reading the value the Runner injects. Because `AUR_HELPER` still resolves
to `paru` (the ladder isn't enabled until ticket 04), this is a behaviour-
preserving migrate batch — the VM happy path stays green throughout.

Scope: the AUR-install call in each shipped program script — firewalld,
apparmor, clamav, rkhunter, ufw, teamspeak3, docker, virt-manager, podman,
zfs-auto-snapshot, borg, and any remaining Security / Backup / Virtualization /
Communication scripts that invoke `paru -S`.

## Acceptance criteria

- [ ] Every `programs/*/install.sh` uses `${AUR_HELPER}` for its AUR install,
      with no literal `paru -S` remaining in those scripts.
- [ ] Each script continues to work when `AUR_HELPER=paru` (unchanged runtime
      behaviour).
- [ ] A grep confirms no `programs/*/install.sh` hardcodes `paru` for the
      install call (comments referencing paru are fine).
- [ ] Existing suite / VM happy path stays green.

## Blocked by

- Ticket 01 (Ladder foundations) — the `AUR_HELPER` export must exist.
