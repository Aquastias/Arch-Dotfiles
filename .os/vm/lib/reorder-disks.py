#!/usr/bin/env python3
# =============================================================================
# vm/_reorder-disks.py — permute data-disk backing files in a libvirt domain
# =============================================================================
# Reads a libvirt domain XML on stdin, reverses the <source file> of every
# data disk EXCEPT the first (the OS disk, which must keep booting), and writes
# the result to stdout. CDROMs are left untouched.
#
# Why: the kernel names SATA disks (/dev/sdX) by controller-port order. Moving
# which qcow2 backs each port renames the disks at boot WITHOUT moving the OS
# disk. A pool recorded by a bare /dev/sdX kernel name then fails to import
# ("one or more devices is currently unavailable"); a pool recorded by a stable
# /dev/disk/by-id or by-partuuid path (the fix) follows its qcow2 and imports
# fine. This is the faithful in-VM reproduction of the multi-disk reorder bug
# (ADR 0028) — pure XML surgery so it is unit-testable without libvirt.
# =============================================================================
import sys
import xml.etree.ElementTree as ET


def reorder(xml_text):
    root = ET.fromstring(xml_text)
    devices = root.find("devices")
    if devices is None:
        return xml_text

    # Data disks only (skip cdroms), in their declared order.
    disks = [d for d in devices.findall("disk")
             if d.get("device", "disk") == "disk"]
    sources = [d.find("source") for d in disks]
    if any(s is None for s in sources) or len(disks) < 3:
        # Need the OS disk + at least two data disks for a meaningful swap.
        return xml_text

    # Keep disk 0 (OS) fixed; reverse the backing files of the rest so the
    # data disks land on different SATA ports at the next boot.
    files = [s.get("file") for s in sources]
    fixed, rest = files[0], files[1:]
    new_files = [fixed] + list(reversed(rest))
    for src, new_file in zip(sources, new_files):
        src.set("file", new_file)

    return ET.tostring(root, encoding="unicode")


if __name__ == "__main__":
    sys.stdout.write(reorder(sys.stdin.read()))
