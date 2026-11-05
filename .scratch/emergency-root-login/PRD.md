# Emergency shell rejects the root password

Status: needs-triage

## Problem

During the 2026-10-31 interrupted-update incident (see
`.scratch/interrupted-update-recovery/PRD.md`), the laptop dropped to
emergency mode and the root password was not accepted: entering it
returned to the same "Give root password for maintenance" prompt.
`passwd -S root` showed a set password (`P`, changed 2026-08-11).
`systemd.debug_shell` also gave no usable shell. Recovery needed
`init=/bin/bash`.

## Open questions

- Wrong password, keymap mismatch in early boot, or sulogin failing
  because modules (e.g. the console keymap/font) could not load?
- Does it reproduce on a current install's emergency target?
- Should the installer guarantee a working maintenance login?
