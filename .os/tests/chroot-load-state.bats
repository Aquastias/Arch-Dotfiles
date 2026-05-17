#!/usr/bin/env bats
# Tests for lib/chroot/load-state.sh — install-state.json reader.

setup() {
  TEST_DIR="$(mktemp -d)"
  export STATE="$TEST_DIR/install-state.json"
}

teardown() { rm -rf "$TEST_DIR"; }

write_state() { printf '%s\n' "$1" > "$STATE"; }

# Minimal valid state file so unrelated jq reads don't error out.
minimal_state() {
  cat <<JSON
{
  "hostname": "h", "timezone": "UTC", "locale": "en_US.UTF-8",
  "keymap": "us", "kernel": "lts", "bootloader": "systemd-boot",
  "rpool": "rpool", "swap": "true", "esp_count": 1,
  "extras": { "backup": false, "security": false }
  $1
}
JSON
}

# ── impermanence fields ──────────────────────────────────────────────────────

@test "load-state: IMPERMANENCE_ENABLED=true when state says enabled" {
  minimal_state ',
  "impermanence": { "enabled": true, "dataset": "rpool/persist",
    "mount": "/persist" }' > "$STATE"
  # shellcheck source=../lib/chroot/load-state.sh
  source "$BATS_TEST_DIRNAME/../lib/chroot/load-state.sh"
  [ "$IMPERMANENCE_ENABLED" = "true" ]
  [ "$IMPERMANENCE_DATASET" = "rpool/persist" ]
  [ "$IMPERMANENCE_MOUNT"   = "/persist" ]
}

@test "load-state: IMPERMANENCE_ENABLED=false when state says disabled" {
  minimal_state ',
  "impermanence": { "enabled": false, "dataset": "rpool/persist",
    "mount": "/persist" }' > "$STATE"
  source "$BATS_TEST_DIRNAME/../lib/chroot/load-state.sh"
  [ "$IMPERMANENCE_ENABLED" = "false" ]
}

@test "load-state: defaults when .impermanence is absent" {
  minimal_state '' > "$STATE"
  source "$BATS_TEST_DIRNAME/../lib/chroot/load-state.sh"
  [ "$IMPERMANENCE_ENABLED" = "false" ]
  [ "$IMPERMANENCE_DATASET" = "rpool/persist" ]
  [ "$IMPERMANENCE_MOUNT"   = "/persist" ]
}

@test "load-state: PERSIST_DIRECTORIES read from .persist.directories" {
  minimal_state ',
  "persist": { "directories": ["/etc/wireguard", "/var/lib/myapp"],
    "files": [] }' > "$STATE"
  source "$BATS_TEST_DIRNAME/../lib/chroot/load-state.sh"
  [ "${#PERSIST_DIRECTORIES[@]}" -eq 2 ]
  [ "${PERSIST_DIRECTORIES[0]}" = "/etc/wireguard" ]
  [ "${PERSIST_DIRECTORIES[1]}" = "/var/lib/myapp" ]
}

@test "load-state: PERSIST_FILES read from .persist.files" {
  minimal_state ',
  "persist": { "directories": [], "files": ["/etc/foo.conf"] }' > "$STATE"
  source "$BATS_TEST_DIRNAME/../lib/chroot/load-state.sh"
  [ "${#PERSIST_FILES[@]}" -eq 1 ]
  [ "${PERSIST_FILES[0]}" = "/etc/foo.conf" ]
}

@test "load-state: PERSIST_* default to empty arrays when absent" {
  minimal_state '' > "$STATE"
  source "$BATS_TEST_DIRNAME/../lib/chroot/load-state.sh"
  [ "${#PERSIST_DIRECTORIES[@]}" -eq 0 ]
  [ "${#PERSIST_FILES[@]}" -eq 0 ]
}
