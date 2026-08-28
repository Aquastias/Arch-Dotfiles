#!/usr/bin/env bash
# lib/chroot/udisks.sh — udisks-ignore rule for ZFS members (ADR 0031)
# Sourced by lib/chroot/configure.sh inside the chroot.

# Pure emitter: prints the udev rule content marking any zfs_member partition
# as ignored by udisks2.
udisks_zfs_ignore_rule() {
  cat <<'RULE'
SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="zfs_member", ENV{UDISKS_IGNORE}="1"
RULE
}

# Thin I/O: writes the rule under <root>/etc/udev/rules.d. <root> defaults to
# "" (i.e. /), which is what configure.sh uses inside the chroot; tests pass a
# temp root. Harmless no-op on a host without udisks2 (the rule just sits
# unread), so it is written unconditionally.
udisks_write_zfs_ignore_rule() {
  local root="${1:-}"
  local dir="${root}/etc/udev/rules.d"
  mkdir -p "$dir"
  udisks_zfs_ignore_rule > "${dir}/90-zfs-member-udisks-ignore.rules"
}
