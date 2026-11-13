# 01: VM Harness waits out the install timeout when no ISO resolved

**What to build:** when the ISO resolver returns nothing (here a transient
`iso-resolver: archlinux.org releases lookup failed`), `vm.sh` logs
`ISO (archzfs-compatible): ` (empty), creates the VM with no boot medium, and
waits the full install timeout (5400 s on `single/guided`) on a firmware
"No bootable option or device" screen. Abort before creating the VM when the
resolved ISO is empty, naming the cause and the `ISO_URL_OVERRIDE` escape
hatch; optionally retry the releases lookup once.

Observed 2026-10-16 (guided run, 90 min lost); retry with
`ISO_URL_OVERRIDE=file:///…/archlinux-2026.10.01-x86_64.iso` passed.

**Blocked by:** None (can start immediately)

**Status:** done

- [x] Empty resolved ISO aborts before VM creation with a clear message
- [x] bats: resolver returning empty → non-zero, no virt-install call

## Comments

Guard lives in `vm_resolve_iso` (empty or missing file → error naming
`ISO_URL_OVERRIDE`); each flow stops on the failed resolve with
`|| exit 1`, before the seed and the VM. No retry added.
