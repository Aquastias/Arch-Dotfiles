#!/usr/bin/env bash
# lib/chroot/zfs-import.sh — decouple the post-boot ZFS import services from
# the deprecated systemd-udev-settle (ADR 0030). Sourced by configure.sh
# inside the chroot.
#
# Why a full replacement unit, not a drop-in: a `[Unit]\nRequires=` reset
# drop-in does NOT remove a dependency declared in the unit's own main file on
# systemd 260 — verified on a booted install, where both zfs-import services
# still showed `Requires=/After=systemd-udev-settle.service` after the drop-in.
# A full unit file at /etc/systemd/system, by contrast, completely shadows the
# /usr/lib one (no merge), so the settle dependency is simply absent. We derive
# it from the package's own shipped unit so it tracks future upstream changes,
# stripping only the settle token.

# Pure filter: reads a systemd unit on stdin and prints it back with
# `systemd-udev-settle.service` removed from every `Requires=`/`After=` line. A
# directive emptied by the removal is dropped entirely; all other content is
# preserved verbatim (token-level removal, so combined lists keep their peers).
zfs_import_strip_settle() {
  awk '
    /^(Requires|After)=/ {
      eq  = index($0, "=")
      key = substr($0, 1, eq)
      n   = split(substr($0, eq + 1), tok, /[ \t]+/)
      out = ""
      for (i = 1; i <= n; i++) {
        if (tok[i] == "" || tok[i] == "systemd-udev-settle.service") continue
        out = (out == "") ? tok[i] : out " " tok[i]
      }
      if (out == "") next          # directive emptied → drop the whole line
      print key out
      next
    }
    { print }
  '
}

# Thin I/O: for each post-boot import service, derive a settle-free full unit
# from the package's shipped copy and install it at <root>/etc/systemd/system,
# where it wholly shadows the <root>/usr/lib unit. <root> defaults to "" (i.e.
# /), which is what configure.sh uses inside the chroot; tests pass a temp root.
# A service whose shipped unit is absent is skipped (the package owns it; we
# never fabricate one).
zfs_import_write_settle_overrides() {
  local root="${1:-}"
  local svc src dst
  for svc in zfs-import-cache zfs-import-scan; do
    src="${root}/usr/lib/systemd/system/${svc}.service"
    dst="${root}/etc/systemd/system/${svc}.service"
    if [[ ! -f "$src" ]]; then
      printf '[zfs-import] %s not found — skipping settle override.\n' \
        "$src" >&2
      continue
    fi
    mkdir -p "$(dirname "$dst")"
    zfs_import_strip_settle < "$src" > "$dst"
  done
}
