Status: done

# Boot-verify: installed system silent after kernel handoff

## Parent

Found while running the dirty-ISO boot-verify fixture
(`01-dirty-iso-boot-verify-fixture.md`) on a libvirt-capable host
(virsh 12.3, qemu 11, /dev/kvm, OVMF). Needs an agent/host with
root + serial access to finish.

## Symptom

With both prereq fixes in place (see "Ruled out") the install
completes `===INSTALLER-EXIT-0===`, the harness power-cycles to the
installed disk, and the serial console shows:

```
BdsDxe: starting Boot0003 "UEFI QEMU HARDDISK ..." (ESP)
   Arch Linux (ZFS — linux-lts)   /   (ZFS — fallback)   /  Firmware
   Boot in 4s ... 3s ... 2s ... 1s
[2J            <-- screen clear at kernel handoff
   <silence for the full BOOT_TIMEOUT_SEC (600s)>
```

→ `_run_boot_verify` returns 125 (no `===FIRSTBOOT-OK===`).
systemd-boot loads from the ESP fine; nothing is observable after
the kernel takes over.

## Why we're blind

Installed cmdline is `root=ZFS=<pool> zfs_import_dir=/dev/disk/by-id
rw` — **no `console=ttyS0`** (by design: the test-only first-boot
unit pings ttyS0 directly once multi-user is reached, so no getty /
console= is needed). Consequence: if boot stalls *before* that unit,
serial shows nothing — kernel/initramfs/ZFS-import messages go to
tty0, not ttyS0.

## Ruled out

- Install reaches `EXIT-0` (was blocked by an install-state
  `--argjson` bug — fixed, see commit
  `fix(installer): Don't concat {} onto core-only host JSON ...`).
- Harness now captures the boot serial (was a PTY race — fixed, see
  `fix(vm): Start boot-verify VM before console capture ...`). The
  systemd-boot menu IS captured, proving capture works.
- First-boot unit was written AND enabled correctly: install log
  shows `zpool import -f -R /mnt rpool`, the unit written to
  `/mnt/etc/systemd/system/firstboot-ok.service`, and
  `ln -sf ../firstboot-ok.service .../multi-user.target.wants/`.
- Impermanence is OFF for the repo's `install.jsonc`, so /etc (and
  the unit symlink) persist across the reboot.

## Hypotheses (untested — need serial visibility)

1. **ZFS import stalls under QEMU SATA.** `zfs_import_dir=/dev/disk/
   by-id` makes the initramfs hook scan by-id only. QEMU SATA disks
   can have a sparse `/dev/disk/by-id`; if the pool member isn't
   there, import finds nothing and boot hangs in a retry loop. (On
   real hardware by-id is well-populated, so the shipped fix works
   there — this would be a VM-only fixture gap, not a regression.)
2. **First-boot unit doesn't fire.** `firstboot-ok.service` has both
   `After=multi-user.target` and `WantedBy=multi-user.target`;
   systemd may drop an edge to break the ordering cycle, so the unit
   never runs even though boot succeeds. Cheap to test in isolation.

## Diagnostic next step (no reinstall)

The installed disk from the run is preserved (domain
`arch-zfs-test-single-dirty`, shut off):
`tests/vm/.vm-test/arch-zfs-test-single-dirty-disk0.qcow2`.

Add a serial console to its loader entry, then boot + capture:

```sh
sudo guestfish -a tests/vm/.vm-test/arch-zfs-test-single-dirty-disk0.qcow2 \
  -m /dev/sda1 \
  write-append /loader/entries/arch-zfs.conf \
  $' console=ttyS0,115200 console=tty0\n'
virsh start arch-zfs-test-single-dirty
script -qfc 'virsh console --force arch-zfs-test-single-dirty' /tmp/boot.log
```

The kernel/initramfs/ZFS-import output then tells us whether it's
hypothesis 1 (import hang → fixture must create the pool by a path
present in QEMU by-id, or the fixture is VM-unfit as-is) or 2 (unit
ordering → fix the unit, re-test).

## Acceptance criteria

- [x] Root cause of the silent boot identified from serial output.
- [x] Fixture reaches `===FIRSTBOOT-OK===` with the shipped fix in place.
      Verified end-to-end on this host (libvirt/KVM): fresh dirty-cache
      install → `===INSTALLER-EXIT-0===` → power-cycle → installed system
      imports root cleanly and emits `===FIRSTBOOT-OK===` (`FIXTURE_EXIT=0`).
- [x] Unblocks `01`'s real-boot AC (positive control verified; the
      revert/negative control is left to `01`).

## Root cause (from serial)

Booted the preserved `arch-zfs-test-single-dirty` disk with
`console=ttyS0` added to the loader entry (offline guestfish edit) and
captured serial. It is **neither hypothesis** — boot dies in the
initramfs, ~2 s in:

```
:: running hook [zfs]
ZFS: Importing pool rpool.
cannot import 'rpool': pool was previously in use from another system.
Last accessed by archiso (hostid=7325101c) at Mon Jun  1 19:31:51 2026
The pool can be imported, use 'zpool import -f' to import the pool.
ERROR: ZFS: Unable to import pool rpool.
Kernel panic - not syncing: Attempted to kill init! exitcode=0x00000100
```

The root pool is stamped **active / "in use by archiso"** (foreign
hostid). The installed initramfs ZFS hook imports without `-f` (correct),
so the import is refused, root can't mount, PID 1 (`/init`) exits 1 →
kernel panic. No `console=` on the stock cmdline is why this was
invisible (the hook's messages go to `/dev/console`).

This is a **fixture bug, not a production bug** (matches the
"works on real hardware" note). Production `finalize.sh` unmounts the
ESP → `zfs umount -a` → `zpool export rpool`, and `/etc/hostid` is copied
into the target (`chroot.sh`), so real installs export cleanly. The
test-only first-boot injection (`_seed_generator_firstboot_block`)
re-imports the pool **on archiso** to drop the sentinel unit, then ran
`zpool export rpool || true` — the `|| true` swallowed a failed export,
leaving the pool active+archiso-stamped. (The seam already warned about
exactly this in its own comment.)

## Fix (TDD)

`lib/seed-generator.sh` — both first-boot blocks now export with a forced
fallback: `zpool export rpool || zpool export -f rpool || true`
(mirrors `02-wipe.sh:495` and finalize's intent). `zpool export -f`
forcibly unmounts any busy dataset and still writes a clean export,
clearing the active flag so the installed system imports root without
`-f`. 2 new `seed-generator.bats` cases (single + multi block assert the
forced fallback). Full bats green (910; the 7 `layout_validate` failures
are pre-existing — real block devices). shellcheck clean.

## Verified (end-to-end)

Re-ran `testing-single-disk-dirty-cache.sh --recreate` on libvirt/KVM
with the fix in place. Result: `Applying Data-Pool Ownership → applied`,
`zpool export rpool`, `===INSTALLER-EXIT-0===`; the power-cycled install
imports root **cleanly** (boot serial: `Import ZFS pools by cache file
[OK] … Reached target ZFS startup target`) and emits `===FIRSTBOOT-OK===`
— `FIXTURE_EXIT=0`. The earlier `Attempted to kill init` panic is gone.

Notes for future runs on this host:
- The 2026.06+ ISOs ship archzfs as **DKMS only**, so the installer
  builds ZFS from source for both the live and target kernels. On 2 vCPU
  that exceeds the 1800s install budget — run with `VM_VCPUS=8`
  (`TIMEOUT_SEC` headroom) or it times out (`FIXTURE_EXIT=124`).
- Two unrelated blockers were fixed to get here: the harness aborts under
  `set -e` when reusing a VM whose CDROMs were ejected
  (`_vm_install_iso_path` empty → use `--recreate`), and a single-mode
  `pool-owners.sh` unbound-variable crash (separate commit `fix(install):
  Guard leftover pool check when storage array undeclared`).
- The negative control (revert the seeding fix / `zfs_import_dir` and
  confirm the fixture fails) is left to `01`.
