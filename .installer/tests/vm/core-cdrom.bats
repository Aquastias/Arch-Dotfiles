#!/usr/bin/env bats
# Tests for _vm_insert_cdroms in vm/lib/core.sh — the rescue re-attach (ADR
# 0099): the install ISO goes into the first cdrom drive and the access seed into
# the second, so a rescue boot lands on the live ISO with SSH + serial. Stubs
# virsh so no real libvirt is needed.

setup() {
  info() { :; }
  warn() { :; }
  section() { :; }
  error() { echo "$*" >&2; return 1; }
  export -f info warn section error
  # shellcheck source=../../vm/lib/core.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/core.sh"
  CALLS="$(mktemp)"
  VM_NAME="rescuevm"
}

teardown() { rm -f "$CALLS"; }

# Two cdrom drives (sda, sdb) reported empty after an eject; change-media logs.
virsh_stub_two_cdroms() {
  virsh() {
    case "$1" in
      domblklist)
        # `--details` column order: Type  Device  Target  Source
        printf '%s\n' \
          "Type   Device   Target   Source" \
          "-------------------------------" \
          "file   cdrom    sda      -" \
          "file   cdrom    sdb      -" \
          "file   disk     vda      /x.qcow2" ;;
      change-media)
        # $2=vm $3=target $4=media --insert --config
        echo "insert $3 $4" >> "$CALLS" ;;
    esac
  }
}

@test "insert: ISO → first cdrom, seed → second cdrom" {
  virsh_stub_two_cdroms
  _vm_insert_cdroms /isos/arch.iso /cache/seed.iso
  grep -q '^insert sda /isos/arch.iso$' "$CALLS"
  grep -q '^insert sdb /cache/seed.iso$' "$CALLS"
}

@test "insert: only the disk (no cdrom drives) → no change-media calls" {
  virsh() {
    case "$1" in
      domblklist) printf '%s\n' "Type Device Target Source" \
        "----" "file disk vda /x.qcow2" ;;
      change-media) echo "insert $3 $4" >> "$CALLS" ;;
    esac
  }
  _vm_insert_cdroms /isos/arch.iso /cache/seed.iso
  [ ! -s "$CALLS" ]
}

@test "insert: seed omitted → only the ISO is inserted" {
  virsh_stub_two_cdroms
  _vm_insert_cdroms /isos/arch.iso
  grep -q '^insert sda /isos/arch.iso$' "$CALLS"
  ! grep -q 'sdb' "$CALLS"
}

# tuned 20261008: each data disk carries a port serial, so the payload can
# pin /dev/sdX to /dev/disk/by-id/ata-QEMU_HARDDISK_vmdisk<i>
@test "_vm_create: every data disk gets the vmdisk<i> serial" {
  virt-install() { printf '%s\n' "$@" > "$CALLS"; }
  CACHE_DIR=/c VM_DISK_SIZES=(60 60 20) VM_RAM_MB=1 VM_VCPUS=1
  FLOW_GRAPHICS_ARGS=()
  _vm_create /iso /seed
  grep -q '^path=/c/rescuevm-disk0.qcow2,.*,serial=vmdisk0$' "$CALLS"
  grep -q '^path=/c/rescuevm-disk2.qcow2,.*,serial=vmdisk2$' "$CALLS"
  ! grep -q 'device=cdrom.*serial=' "$CALLS"
}
