# 08: Undo Last Update

Status: ready-for-agent

PRD: `.scratch/interrupted-update-recovery/PRD.md`, ADR 0166.

**What to build:** one "Undo Last Update" boot entry on all five loaders.
Choosing it rolls the Update Snapshot datasets back to the newest Update
Snapshot in the initramfs (after pool import and unlock, before the
Impermanence Rollback Hook), restores the matching Blank Snapshots on
Impermanence hosts, and boots the Primary Kernel's `-prev` pair. The entry
is absent while that pair is absent. Entries use stable names, so efistub
NVRAM entries are written once.

**Blocked by:** 01, 06, 07.

- [ ] Bats: entry rendered for each of the five loaders; absent without a
      previous Primary Kernel pair
- [ ] VM: complete an update, boot Undo, previous kernel and package
      versions are back, normal boot afterwards
- [ ] VM on an Impermanence profile: `/etc` matches the rolled-back `/usr`
- [ ] Retrofit adds the entry where the ESP holds a previous pair
