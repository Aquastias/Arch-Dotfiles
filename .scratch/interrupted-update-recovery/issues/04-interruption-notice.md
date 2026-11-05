# 04: Interruption notice

Status: ready-for-agent

PRD: `.scratch/interrupted-update-recovery/PRD.md`, ADR 0166.

**What to build:** after a boot that needed a Stash Restore, the operator
sees a console message during boot and a desktop notification after login
saying the last update was interrupted and to run `sudo pacman -Syu`. The
notice clears once a pacman transaction completes. Nothing runs pacman.

**Blocked by:** 03.

- [ ] Console message on a Stash Restore boot only
- [ ] Desktop notification after login, every supported session
- [ ] Notice gone after a completed transaction
- [ ] VM (01 recipe): both notices seen
