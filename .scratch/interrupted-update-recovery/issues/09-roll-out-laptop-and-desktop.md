# 09: Roll out to the laptop and desktop

Status: done

PRD: `.scratch/interrupted-update-recovery/PRD.md`, ADR 0166.

**What to build:** run the retrofit tool on the laptop and the desktop so
both get the Module Stash, Stash Restore, notice, battery preflight,
previous kernel pairs, Update Snapshot and Undo Last Update.

**Blocked by:** 03, 04, 05, 06, 07, 08.

- [x] Dry run reviewed on each machine, then applied
- [x] Undo Last Update entry visible in each boot menu after the next
      kernel update
- [x] Update Snapshots appear after a pacman run
