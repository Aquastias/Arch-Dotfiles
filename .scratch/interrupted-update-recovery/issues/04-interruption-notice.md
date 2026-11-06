# 04: Interruption notice

Status: ready-for-agent

PRD: `.scratch/interrupted-update-recovery/PRD.md`, ADR 0166.

**What to build:** after a boot that needed a Stash Restore, the operator
sees a console message during boot and a desktop notification after login
saying the last update was interrupted and to run `sudo pacman -Syu`. The
notice clears once a pacman transaction completes. Nothing runs pacman.

**Blocked by:** 03.

- [x] Console message on a Stash Restore boot only
- [ ] Desktop notification after login, every supported session
- [x] Notice gone after a completed transaction
- [ ] VM (01 recipe): both notices seen

## Comments

- Code + bats done. Console: the restore unit prints the notice with
  `StandardOutput=journal+console`. Desktop: a user unit enabled from the
  vendor `default.target.wants` (Hyprland runs no XDG autostart, ADR 0162),
  sending the notification over `gdbus` (glib2) after waiting for a
  notification server; no libnotify dependency. Shown at every login until
  the ESP Kernel Sync drops the stash.
- The notice says `sudo pacman -S <kernel pkgbases>`, not `pacman -Syu`: the
  database already lists the new kernel, so only a reinstall re-runs the
  missed hooks.
- Open: "every supported session" and the VM check (needs ticket 01).
- VM finding: `pacman -S <kernel>` is unsafe (a newer repo kernel without
  matching headers breaks zfs-dkms; reinstalling a restored version
  conflicts) and the interrupted transaction leaves `db.lck`. The notice now
  names `sudo /usr/local/lib/archzfs/boot-recovery.sh finish`, and a boot unit
  clears the stale lock.
