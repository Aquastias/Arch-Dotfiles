#!/usr/bin/env bash
# =============================================================================
# vm/lib/reorder-disks.sh — permute data-disk backing files in a libvirt domain
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
#
# Bash + awk, no python (repo policy: no Python scripts, see docs/agents).
# =============================================================================
set -euo pipefail

exec awk -f "${BASH_SOURCE[0]%/*}/reorder-disks.awk"
