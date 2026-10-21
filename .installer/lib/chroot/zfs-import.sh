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
# parent_directory / base_name — the chroot-world path helpers (sibling).
# shellcheck source=./chroot-common.sh
declare -F parent_directory >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/chroot-common.sh"

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
  local service source_path destination
  for service in zfs-import-cache zfs-import-scan; do
    source_path="${root}/usr/lib/systemd/system/${service}.service"
    destination="${root}/etc/systemd/system/${service}.service"
    if [[ ! -f "$source_path" ]]; then
      printf '[zfs-import] %s not found — skipping settle override.\n' \
        "$source_path" >&2
      continue
    fi
    mkdir -p "$(parent_directory "$destination")"
    zfs_import_strip_settle < "$source_path" > "$destination"
  done
}

# Ship a zfs-load-key@.service TEMPLATE so an encrypted DATA pool auto-loads its
# key POST-boot from its keylocation (a keyfile on the already-mounted root,
# ADR 0043), ordered BEFORE zfs-mount.service mounts the datasets — so the
# operator types no second secret. Upstream OpenZFS ships no such template, so
# configure.sh's `systemctl enable zfs-load-key@<pool>` needs this file. The
# root pool is unlocked by the initramfs (keylocation=prompt) and must NOT use
# this unit. <root> defaults to "" (the chroot's /); tests pass a temp root.
zfs_import_write_load_key_template() {
  local root="${1:-}"
  local destination="${root}/etc/systemd/system/zfs-load-key@.service"
  mkdir -p "$(parent_directory "$destination")"
  cat > "$destination" <<'UNIT'
[Unit]
Description=Load ZFS encryption key for %i
Documentation=man:zfs-load-key(8)
DefaultDependencies=no
After=zfs-import.target
Before=zfs-mount.service
Wants=zfs-import.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/zfs load-key %i

[Install]
WantedBy=zfs-mount.service
UNIT
}

# Write the zfs-mount-generator cache for <pool> with the EXACT property set +
# order the generator parses — the OpenZFS cacher's canonical `zfs list -o` list:
# the 12 real props (name…keylocation) plus the 8 `org.openzfs.systemd:*`
# user-props (emitted as `-` when unset). The repo's older 8-column set was
# MISALIGNED (`readonly` sat where the generator expects `devices`), so the
# generator bailed with exit 1 and produced no units — zfs-mount.service was the
# real mounter. Matching the canonical order makes the generator parse cleanly.
# <dir> defaults to the live /etc/zfs/zfs-list.cache; tests pass a temp dir.
# Best-effort (|| true): a pool that can't be listed leaves no cache file
# (zfs-mount.service still mounts it).
zfs_import_write_list_cache() {
  local pool="$1" directory="${2:-/etc/zfs/zfs-list.cache}"
  mkdir -p "$directory"
  zfs list -H -t filesystem -o \
name,mountpoint,canmount,atime,relatime,devices,exec,readonly,setuid,nbmand,encroot,keylocation,org.openzfs.systemd:requires,org.openzfs.systemd:requires-mounts-for,org.openzfs.systemd:before,org.openzfs.systemd:after,org.openzfs.systemd:wanted-by,org.openzfs.systemd:required-by,org.openzfs.systemd:nofail,org.openzfs.systemd:ignore \
    "$pool" 2>/dev/null > "${directory}/${pool}" || true
}

# zfs_import_write_mount_retry_dropin [root] — retry a crashed `zfs mount -a`
# inside zfs-mount.service's start job: it aborts now and then in libzfs's
# parallel mount (no-shell 20261007, noctalia-greeter 20261021). Restart= is
# no use: systemd releases every After= unit when the first start fails, so
# the /persist bind mounts ran (and failed) before the restart. Three tries,
# 2 s apart; a mounted dataset is skipped on retry. `$$` is systemd's `$`.
zfs_import_write_mount_retry_dropin() {
  local directory="${1:-}/etc/systemd/system/zfs-mount.service.d"
  mkdir -p "$directory"
  cat > "$directory/10-retry.conf" <<'UNIT'
[Service]
ExecStart=
ExecStart=/bin/sh -c 'n=1; until zfs mount -a; do [ "$$n" -lt 3 ] || exit 1; n=$$((n + 1)); sleep 2; done'
UNIT
}
