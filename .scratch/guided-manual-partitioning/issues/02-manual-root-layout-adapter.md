# 02 — Manual Root Layout Adapter + dispatch (back-end installs from a config)

**What to build:** The back-end that turns a manual plan into a booting system.
A new Root Layout Adapter, dispatched when `disk_config.kind == manual`, consumes
the planner's output: it formats only the partitions marked `format`, mounts
every assigned partition at its mountpoint under `MOUNT_ROOT`, activates any
`[swap]` partition, and publishes the filesystem-blind boot record — **without
whole-disk wiping** (the operator's partition table is authoritative). Demoable
before any UI exists: an Effective Config with `kind: manual` + a hand-written
`partitions[]` installs and boots in a VM.

**Blocked by:** 01.

**Status:** ready-for-agent

- [ ] `dispatch.sh` gains a kind branch: `manual` sources the manual adapter;
      every filesystem × mode path is unchanged.
- [ ] The adapter `mkfs`'s only partitions with `format=true`; keep-marked
      partitions are mounted with their existing data intact.
- [ ] Each assigned partition mounts at its mountpoint under `MOUNT_ROOT`; a
      `[swap]` partition is `mkswap`'d + swapped on.
- [ ] The ESP is mounted and the boot record is published so the installed
      system boots — no pool machinery involved.
- [ ] No `wipefs`/`--zap-all` of the whole disk occurs on the manual path.
- [ ] A VM case seeded with a hand-written manual config (scripted partition
      table, no guided UI) installs and boots, verified via the existing VM
      harness / `vm/vm-pool-verify.bats` prior art.
