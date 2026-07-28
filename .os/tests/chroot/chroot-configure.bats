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

# ── _resolve_root_password ────────────────────────────────────────────────────
# The single host-side owner of the final root password: a Host Secret's
# .root_password overrides the collected/default value; the .secrets /
# .guided_passwords precedence is delegated to install_state_credential_path.
# STATE is the secrets-bearing /mnt/install-state.json.
STATE() { printf '%s' "$MOUNT_ROOT/install-state.json"; }

@test "uses .root_password from the SOPS host secret (.secrets.host)" {
  local host_sec="$TEST_DIR/host-secrets.json"
  printf '{"root_password":"s3cr3t"}\n' > "$host_sec"
  printf '{"secrets":{"host":"%s"}}\n' "$host_sec" > "$(STATE)"

  run _resolve_root_password "collected" "$(STATE)"
  [ "$status" -eq 0 ]
  [ "$output" = "s3cr3t" ]
}

@test "uses .root_password from the no-SOPS guided seam (.guided_passwords.host)" {
  local host_sec="$TEST_DIR/host-secrets.json"
  printf '{"root_password":"guided"}\n' > "$host_sec"
  printf '{"guided_passwords":{"host":"%s"}}\n' "$host_sec" > "$(STATE)"

  run _resolve_root_password "collected" "$(STATE)"
  [ "$output" = "guided" ]
}

@test "falls back to the collected value when the secret lacks root_password" {
  local host_sec="$TEST_DIR/host-secrets.json"
  printf '{"other_field":"value"}\n' > "$host_sec"
  printf '{"secrets":{"host":"%s"}}\n' "$host_sec" > "$(STATE)"

  run _resolve_root_password "collected" "$(STATE)"
  [ "$output" = "collected" ]
}

@test "falls back to the collected value when there is no secrets.host entry" {
  printf '{"secrets":{}}\n' > "$(STATE)"
  run _resolve_root_password "collected" "$(STATE)"
  [ "$output" = "collected" ]
}

@test "falls back to the collected value when the state file is absent" {
  run _resolve_root_password "collected" "$(STATE)"
  [ "$output" = "collected" ]
}

@test "falls back to the collected value when secrets.host points to a missing file" {
  printf '{"secrets":{"host":"/nonexistent/host-secrets.json"}}\n' > "$(STATE)"
  run _resolve_root_password "collected" "$(STATE)"
  [ "$output" = "collected" ]
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

# ── enable_optional_services: sshd toggle (issue 05) ─────────────────────────
# options.ssh.enabled flips sshd.service; openssh is already pacstrapped.

@test "enable_optional_services enables sshd when SSH_ENABLED=true" {
  _load_base_services
  SSH_ENABLED=true enable_optional_services
  grep -qx "systemctl enable sshd.service" "$SYSCTL_LOG"
}

@test "enable_optional_services does not enable sshd when SSH_ENABLED=false" {
  _load_base_services
  SSH_ENABLED=false enable_optional_services
  ! grep -q "sshd" "$SYSCTL_LOG"
}

@test "enable_optional_services does not enable sshd when SSH_ENABLED unset" {
  _load_base_services
  enable_optional_services
  ! grep -q "sshd" "$SYSCTL_LOG"
}

@test "enable_base_services masks the network-online wait stall" {
  _load_base_services
  enable_base_services
  grep -qx "systemctl mask systemd-networkd-wait-online.service" "$SYSCTL_LOG"
  grep -qx "systemctl mask NetworkManager-wait-online.service" "$SYSCTL_LOG"
}
