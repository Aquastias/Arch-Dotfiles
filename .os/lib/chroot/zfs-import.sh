#!/usr/bin/env bash
# lib/chroot/zfs-import.sh — decouple the post-boot ZFS import services from
# the deprecated systemd-udev-settle (ADR 0030). Sourced by configure.sh
# inside the chroot.

# Pure emitter: prints the systemd drop-in that removes the
# Requires=/After=systemd-udev-settle.service relationship from a ZFS import
# service. Resets both lists, then re-adds the non-settle ordering that still
# matters (cryptsetup for encrypted pools).
zfs_import_settle_dropin() {
  cat <<'DROPIN'
[Unit]
Requires=
After=
After=cryptsetup.target
DROPIN
}

# Thin I/O: writes the drop-in under <root>/etc/systemd/system for both the
# cache-import and scan-import services. <root> defaults to "" (i.e. /), which
# is what configure.sh uses inside the chroot; tests pass a temp root.
zfs_import_write_settle_dropins() {
  local root="${1:-}"
  local svc dir
  for svc in zfs-import-cache zfs-import-scan; do
    dir="${root}/etc/systemd/system/${svc}.service.d"
    mkdir -p "$dir"
    zfs_import_settle_dropin > "${dir}/10-no-udev-settle.conf"
  done
}
