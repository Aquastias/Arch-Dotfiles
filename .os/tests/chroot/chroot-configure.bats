#!/usr/bin/env bats
# Tests for chroot.sh secrets staging helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export MOUNT_ROOT="$TEST_DIR/mnt"
  mkdir -p "$MOUNT_ROOT/root/lib-chroot"

  # Stubs for common.sh functions referenced at source time or by helpers
  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; exit 1; }
  section() { :; }
  export -f info warn error section

  # shellcheck source=../../lib/chroot.sh
  source "$BATS_TEST_DIRNAME/../../lib/chroot.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── _chroot_resolve_host_secrets ──────────────────────────────────────────────

@test "returns chroot path and stages file when host secrets present" {
  local host_sec="$TEST_DIR/host-secrets.json"
  printf '{"root_password":"r00t"}\n' > "$host_sec"
  printf '{"secrets":{"host":"%s"}}\n' "$host_sec" \
    > "$MOUNT_ROOT/install-state.json"

  run _chroot_resolve_host_secrets
  [ "$status" -eq 0 ]
  [ "$output" = "/root/lib-chroot/host-secrets.json" ]
  [ -f "$MOUNT_ROOT/root/lib-chroot/host-secrets.json" ]
}

@test "returns empty when no secrets.host entry" {
  printf '{"secrets":{}}\n' > "$MOUNT_ROOT/install-state.json"

  run _chroot_resolve_host_secrets
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "returns empty when install-state.json absent" {
  run _chroot_resolve_host_secrets
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "returns empty when secrets.host points to missing file" {
  printf '{"secrets":{"host":"/nonexistent/host-secrets.json"}}\n' \
    > "$MOUNT_ROOT/install-state.json"

  run _chroot_resolve_host_secrets
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── _chroot_seed_zpool_cache ──────────────────────────────────────────────────

@test "seeds a valid zpool.cache one pool per zpool set call" {
  # Real zpool: `set cachefile=PATH pool` accepts exactly ONE pool; >1 errors.
  zpool() {
    [ "$1" = set ] || return 0
    shift
    local kv="$1"; shift
    [ "$#" -eq 1 ] || return 2
    printf 'cache:%s\n' "$1" >> "${kv#cachefile=}"
  }
  export -f zpool

  run _chroot_seed_zpool_cache "$MOUNT_ROOT/etc/zfs/zpool.cache" rpool dpool
  [ "$status" -eq 0 ]
  [ -s "$MOUNT_ROOT/etc/zfs/zpool.cache" ]
  grep -q '^cache:rpool$' "$MOUNT_ROOT/etc/zfs/zpool.cache"
  grep -q '^cache:dpool$' "$MOUNT_ROOT/etc/zfs/zpool.cache"
}

@test "removes any stale cache when a pool's cachefile cannot be set" {
  # The laptop bug: leaving a corrupt/stale cache makes the initramfs ZFS hook
  # loop on "invalid or corrupt cache file". On failure we must leave NO cache.
  zpool() { return 1; }
  export -f zpool
  mkdir -p "$MOUNT_ROOT/etc/zfs"
  printf 'stale-garbage\n' > "$MOUNT_ROOT/etc/zfs/zpool.cache"

  run _chroot_seed_zpool_cache "$MOUNT_ROOT/etc/zfs/zpool.cache" rpool dpool
  [ "$status" -eq 0 ]
  [ ! -e "$MOUNT_ROOT/etc/zfs/zpool.cache" ]
}

# ── enable_base_services (lib/chroot/base-services.sh) ─────────────────────────
# The Chroot Configuration Module enables the always-on base daemons through
# this helper. Stub systemctl, source the helper, assert each enable lands.

_load_base_services() {
  SYSCTL_LOG="$TEST_DIR/systemctl.log"
  : > "$SYSCTL_LOG"
  systemctl() { echo "systemctl $*" >> "$SYSCTL_LOG"; }
  # shellcheck source=../../lib/chroot/base-services.sh
  source "$BATS_TEST_DIRNAME/../../lib/chroot/base-services.sh"
}

@test "enable_base_services enables NetworkManager, resolved, and timesyncd" {
  _load_base_services
  enable_base_services
  grep -qx "systemctl enable NetworkManager"    "$SYSCTL_LOG"
  grep -qx "systemctl enable systemd-resolved"  "$SYSCTL_LOG"
  grep -qx "systemctl enable systemd-timesyncd" "$SYSCTL_LOG"
}

@test "enable_base_services enables cronie alongside the base daemons" {
  _load_base_services
  enable_base_services
  grep -qx "systemctl enable cronie" "$SYSCTL_LOG"
}
