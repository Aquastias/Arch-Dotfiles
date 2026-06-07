#!/usr/bin/env bats
# Tests for vm/lib/reorder-disks.py — permutes data-disk backing files so the next
# boot renames /dev/sdX, the faithful in-VM repro of the multi-disk reorder bug
# (ADR 0028). Pure XML in → XML out; no libvirt touched.

SCRIPT="$BATS_TEST_DIRNAME/../../vm/lib/reorder-disks.py"

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

# Returns the source file backing a given target dev, post-transform.
_src_for() {
  printf '%s' "$1" | python3 -c '
import sys, re, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read()); dev = sys.argv[1]
for d in root.find("devices").findall("disk"):
    if d.find("target").get("dev") == dev:
        print(d.find("source").get("file")); break
' "$2"
}

@test "reorder: OS disk (sda) keeps its backing file" {
  out="$(_domain_xml | python3 "$SCRIPT")"
  [ "$(_src_for "$out" sda)" = "/img/disk0.qcow2" ]
}

@test "reorder: data disks' backing files are reversed" {
  out="$(_domain_xml | python3 "$SCRIPT")"
  [ "$(_src_for "$out" sdb)" = "/img/disk3.qcow2" ]
  [ "$(_src_for "$out" sdc)" = "/img/disk2.qcow2" ]
  [ "$(_src_for "$out" sdd)" = "/img/disk1.qcow2" ]
}

@test "reorder: the cdrom is left untouched" {
  out="$(_domain_xml | python3 "$SCRIPT")"
  [ "$(_src_for "$out" sde)" = "/img/install.iso" ]
}

@test "reorder: a domain with too few data disks is unchanged" {
  small='<domain><devices>
    <disk device="disk"><source file="/a"/><target dev="sda"/></disk>
    <disk device="disk"><source file="/b"/><target dev="sdb"/></disk>
  </devices></domain>'
  out="$(printf '%s' "$small" | python3 "$SCRIPT")"
  [ "$(_src_for "$out" sda)" = "/a" ]
  [ "$(_src_for "$out" sdb)" = "/b" ]
}
