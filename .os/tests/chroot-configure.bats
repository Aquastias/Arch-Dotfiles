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

  # shellcheck source=../lib/chroot.sh
  source "$BATS_TEST_DIRNAME/../lib/chroot.sh"
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
