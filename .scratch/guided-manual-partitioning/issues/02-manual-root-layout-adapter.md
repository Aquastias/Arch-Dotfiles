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

**Status:** done

- [x] `dispatch.sh` gains a kind branch: `manual` sources the manual adapter;
      every filesystem × mode path is unchanged.
- [x] The adapter `mkfs`'s only partitions with `format=true`; keep-marked
      partitions are mounted with their existing data intact.
- [x] Each assigned partition mounts at its mountpoint under `MOUNT_ROOT`; a
      `[swap]` partition is `mkswap`'d + swapped on.
- [x] The ESP is mounted and the boot record is published so the installed
      system boots — no pool machinery involved.
- [x] No `wipefs`/`--zap-all` of the whole disk occurs on the manual path.
- [x] A VM case seeded with a hand-written manual config (scripted partition
      table, no guided UI) installs and boots, verified via the existing VM
      harness / `vm/vm-pool-verify.bats` prior art.

## Comments

- 2026-09-27 audit: 9a41d8f, f2c2216 (layout/manual/root.sh, dispatch kind
  branch; manual-dispatch.bats). The VM case was never added — tracked in 05.

- 2026-09-27 audit: the VM case now exists and passes — see issue 05's audit
  note (2026-09-27).
