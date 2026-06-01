Status: ready-for-agent

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

- [ ] Root cause of the silent boot identified from serial output.
- [ ] Either: fixture reaches `===FIRSTBOOT-OK===` with the shipped
      fix in place; or: documented why the dirty-cache fixture can't
      assert real boot under QEMU and what it guards instead.
- [ ] Unblocks `01`'s remaining ACs (real-boot + negative control).
