#!/usr/bin/env bats
# Tests for vm/lib/reorder-disks — permutes data-disk backing files so the next
# boot renames /dev/sdX, the faithful in-VM repro of the multi-disk reorder bug
# (ADR 0028). Pure XML in → XML out; no libvirt touched. Bash + awk, no python.

SCRIPT="$BATS_TEST_DIRNAME/../../vm/lib/reorder-disks"

# A minimal domain: OS disk (sda) + three data disks (sdb/sdc/sdd) + a cdrom.
_domain_xml() {
  cat <<'XML'
<domain type='kvm'><devices>
  <disk type='file' device='disk'>
    <source file='/img/disk0.qcow2'/><target dev='sda' bus='sata'/>
  </disk>
  <disk type='file' device='disk'>
    <source file='/img/disk1.qcow2'/><target dev='sdb' bus='sata'/>
  </disk>
  <disk type='file' device='disk'>
    <source file='/img/disk2.qcow2'/><target dev='sdc' bus='sata'/>
  </disk>
  <disk type='file' device='disk'>
    <source file='/img/disk3.qcow2'/><target dev='sdd' bus='sata'/>
  </disk>
  <disk type='file' device='cdrom'>
    <source file='/img/install.iso'/><target dev='sde' bus='sata'/>
  </disk>
</devices></domain>
XML
}

# Returns the source file backing a given target dev, post-transform. source and
# target sit on one line, so grab the file= on the line carrying this dev=.
# Quote-agnostic (virsh emits single quotes; the too-few fixture uses double).
_src_for() {
  printf '%s' "$1" | grep -E "dev=['\"]$2['\"]" | head -1 \
    | grep -oE "file=['\"][^'\"]*['\"]" | head -1 \
    | sed -E "s/file=['\"]//; s/['\"]$//"
}

@test "reorder: OS disk (sda) keeps its backing file" {
  out="$(_domain_xml | "$SCRIPT")"
  [ "$(_src_for "$out" sda)" = "/img/disk0.qcow2" ]
}

@test "reorder: data disks' backing files are reversed" {
  out="$(_domain_xml | "$SCRIPT")"
  [ "$(_src_for "$out" sdb)" = "/img/disk3.qcow2" ]
  [ "$(_src_for "$out" sdc)" = "/img/disk2.qcow2" ]
  [ "$(_src_for "$out" sdd)" = "/img/disk1.qcow2" ]
}

@test "reorder: the cdrom is left untouched" {
  out="$(_domain_xml | "$SCRIPT")"
  [ "$(_src_for "$out" sde)" = "/img/install.iso" ]
}

@test "reorder: a domain with too few data disks is unchanged" {
  small='<domain><devices>
    <disk device="disk"><source file="/a"/><target dev="sda"/></disk>
    <disk device="disk"><source file="/b"/><target dev="sdb"/></disk>
  </devices></domain>'
  out="$(printf '%s' "$small" | "$SCRIPT")"
  [ "$(_src_for "$out" sda)" = "/a" ]
  [ "$(_src_for "$out" sdb)" = "/b" ]
}
