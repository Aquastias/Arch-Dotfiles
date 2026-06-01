Status: ready-for-agent

# Dirty-ISO boot-verify VM fixture

## Parent

Follow-up to the ZFS root boot bug fixed in
`fix(installer): Per-pool zpool.cache + zfs_import_dir boot guard`.

## Why

VM smoke tests verify the installer *runs* (sentinel
`===INSTALLER-EXIT-0===`) but `--noreboot` means they never boot the
installed HD system. The original brick — a corrupt `zpool.cache`
baked into the initramfs — passed every VM test and only failed on
real hardware (laptop `chronos`). VMs survived because their live
ISO had no stale `/etc/zfs/zpool.cache`; the laptop's did. We need a
fixture that reproduces the dirty-ISO condition AND asserts the
installed system boots.

## What to build

A new VM fixture + harness capability that, behind an opt-in flag,
power-cycles to the installed disk and confirms it boots.

1. **Dirty-ISO pre-seed.** Before running the installer, the
   fixture's user-data writes garbage to `/etc/zfs/zpool.cache` on
   the live system (reproduces the laptop's dirty ISO).
2. **First-boot serial sentinel (test-only).** After install
   succeeds, the user-data re-imports the pool at a temp altroot and
   drops a oneshot unit into the new root:
   `ExecStart=/bin/sh -c 'echo ===FIRSTBOOT-OK=== >/dev/ttyS0'`,
   `ExecStartPost=/bin/systemctl disable firstboot-ok`. Writing
   straight to `/dev/ttyS0` needs no `console=` cmdline and no
   getty. Export, then emit `===INSTALLER-EXIT-0===` + poweroff as
   today. This injection lives in the test env / seed-generator path
   ONLY — the production installer never ships it.
3. **Harness `--verify-boot` phase.** After the install sentinel,
   eject both cdroms (ISO + seed) via virsh so UEFI boots the ESP
   (systemd-boot removable `BOOTX64.EFI`), restart, re-capture the
   serial console, and wait for `===FIRSTBOOT-OK===` under a boot
   timeout.
4. **Generalize sentinel-watcher.** Add a marker-agnostic wait
   (e.g. `sentinel_watcher_wait_marker LOG MARKER TIMEOUT`) so the
   harness can wait on `===FIRSTBOOT-OK===` as well as the existing
   exit sentinel. Keep the exit-code parser intact.
5. **Dedicated env script.** A single fixture (e.g.
   `testing-single-disk-dirty-cache.sh`) sets `--verify-boot`,
   carries the dirty-cache + first-boot-unit user-data steps, and is
   the only env that runs the boot phase. Other envs unchanged.

## Acceptance criteria

- [ ] Fixture pre-seeds a garbage `/etc/zfs/zpool.cache` on the live
      ISO before install.
- [ ] After a successful install, the harness power-cycles to the
      installed disk (cdroms ejected) and the installed system
      reaches `===FIRSTBOOT-OK===` on serial within the boot timeout.
- [ ] The first-boot sentinel unit self-disables and is injected
      test-only — a normal (non-fixture) install never contains it.
- [x] `sentinel-watcher` waits on an arbitrary marker; existing
      `INSTALLER-EXIT-N` parsing unchanged (regression-covered in
      `sentinel-watcher.bats`).
- [ ] The boot phase is opt-in (`--verify-boot`); the default VM
      suite's runtime/behaviour is unchanged for other fixtures.
- [ ] With the shipped fix in place the fixture passes; reverting
      either the per-pool seeding loop or `zfs_import_dir` makes it
      fail (proves it guards the real bug class).

## Notes

- `zfs_import_dir=/dev/disk/by-id` on the boot cmdline means a bad
  cache cannot brick boot regardless; this fixture also guards that.
- Heavy (~doubles fixture runtime) — keep it out of the fast path.

## Comments

- Item 4 done (TDD): `sentinel_watcher_wait_marker LOG MARKER TIMEOUT` in
  `lib/sentinel-watcher.sh` — fixed-substring match, returns 0/124/2, same
  late-creation + no-mutation contract; 6 new `sentinel-watcher.bats` cases
  (found, timeout, late-arrival, serial CRLF, empty-marker, bad-timeout).
  Remaining: items 1-3, 5 (dirty-cache pre-seed, first-boot unit injection,
  harness `--verify-boot` phase, dedicated env script). Status stays
  `ready-for-agent`.
