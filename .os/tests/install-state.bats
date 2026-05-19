#!/usr/bin/env bats
# Tests for lib/install-state.sh — host↔chroot wire format.

setup() {
  TEST_DIR="$(mktemp -d)"
  STATE="$TEST_DIR/install-state.json"
  # shellcheck source=../lib/install-state.sh
  source "$BATS_TEST_DIRNAME/../lib/install-state.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# Full valid state covering every schema field.
valid_state() {
  cat <<'JSON' > "$STATE"
{
  "hostname": "h", "timezone": "UTC", "locale": "en_US.UTF-8",
  "keymap": "us", "kernel": "lts", "bootloader": "systemd-boot",
  "rpool": "rpool", "swap": true, "esp_count": 1,
  "extras":       { "backup": false, "security": false },
  "impermanence": { "enabled": false, "dataset": "rpool/persist",
                    "mount": "/persist" },
  "persist":      { "directories": [], "files": [] }
}
JSON
}

drop_field() {
  local path="$1" tmp
  tmp="$(mktemp)"
  jq "del($path)" "$STATE" > "$tmp" && mv "$tmp" "$STATE"
}

set_field() {
  local path="$1" value="$2" tmp
  tmp="$(mktemp)"
  jq "$path = $value" "$STATE" > "$tmp" && mv "$tmp" "$STATE"
}

# ── install_state_load: scalar ───────────────────────────────────────────────

@test "install_state_load: sets HOSTNAME from .hostname" {
  valid_state
  install_state_load "$STATE"
  [ "$HOSTNAME" = "h" ]
}

# ── install_state_load: nested bool ──────────────────────────────────────────

@test "install_state_load: sets EXTRAS_BACKUP from nested bool" {
  valid_state
  set_field '.extras.backup' 'true'
  install_state_load "$STATE"
  [ "$EXTRAS_BACKUP" = "true" ]
}

@test "install_state_load: EXTRAS_BACKUP=false preserved" {
  valid_state
  install_state_load "$STATE"
  [ "$EXTRAS_BACKUP" = "false" ]
}

# ── install_state_load: array ────────────────────────────────────────────────

@test "install_state_load: PERSIST_DIRECTORIES from .persist.directories" {
  valid_state
  set_field '.persist.directories' '["/etc/wireguard","/var/lib/myapp"]'
  install_state_load "$STATE"
  [ "${#PERSIST_DIRECTORIES[@]}" -eq 2 ]
  [ "${PERSIST_DIRECTORIES[0]}" = "/etc/wireguard" ]
  [ "${PERSIST_DIRECTORIES[1]}" = "/var/lib/myapp" ]
}

@test "install_state_load: PERSIST_DIRECTORIES empty when array empty" {
  valid_state
  install_state_load "$STATE"
  [ "${#PERSIST_DIRECTORIES[@]}" -eq 0 ]
}

# ── install_state_load: missing field is an error ────────────────────────────

@test "install_state_load: returns 1 + names field when scalar missing" {
  valid_state
  drop_field '.hostname'
  run install_state_load "$STATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *".hostname"* ]]
}

@test "install_state_load: returns 1 when nested bool missing" {
  valid_state
  drop_field '.extras.backup'
  run install_state_load "$STATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *".extras.backup"* ]]
}

@test "install_state_load: returns 1 when array missing" {
  valid_state
  drop_field '.persist.directories'
  run install_state_load "$STATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *".persist.directories"* ]]
}

# ── install_state_load: missing file ─────────────────────────────────────────

@test "install_state_load: returns 1 + names path when file missing" {
  run install_state_load "$TEST_DIR/does-not-exist.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing file"* ]]
  [[ "$output" == *"does-not-exist.json"* ]]
}

# ── install_state_write ──────────────────────────────────────────────────────

setup_writer_globals() {
  RESOLVED_HOSTNAME="box01"
  install_config_timezone()             { echo "UTC"; }
  install_config_locale()               { echo "en_US.UTF-8"; }
  install_config_keymap()               { echo "us"; }
  install_config_kernel()               { echo "lts"; }
  install_config_bootloader()           { echo "systemd-boot"; }
  install_config_swap_enabled()         { echo "true"; }
  install_config_extras_backup()        { echo "false"; }
  install_config_extras_security()      { echo "false"; }
  install_config_impermanence_enabled() { echo "false"; }
  install_config_impermanence_dataset() { echo "rpool/persist"; }
  install_config_impermanence_mount()   { echo "/persist"; }
  LAYOUT_OS_POOL_NAME="rpool"
  LAYOUT_ESP_PARTS=(/dev/nvme0n1p1)
  INSTALL_STATE_HOST_JSON='{}'
}

@test "install_state_write: writes .hostname from RESOLVED_HOSTNAME" {
  setup_writer_globals
  install_state_write "$STATE"
  [ "$(jq -r .hostname "$STATE")" = "box01" ]
}

@test "install_state_write: assembles full schema with nested objects" {
  setup_writer_globals
  LAYOUT_ESP_PARTS=(/dev/nvme0n1p1 /dev/nvme1n1p1)
  INSTALL_STATE_HOST_JSON='{"persist":{"directories":["/etc/wireguard"],
    "files":["/etc/foo"]}}'
  install_state_write "$STATE"

  [ "$(jq -r .hostname     "$STATE")" = "box01" ]
  [ "$(jq -r .timezone     "$STATE")" = "UTC" ]
  [ "$(jq -r .locale       "$STATE")" = "en_US.UTF-8" ]
  [ "$(jq -r .keymap       "$STATE")" = "us" ]
  [ "$(jq -r .kernel       "$STATE")" = "lts" ]
  [ "$(jq -r .bootloader   "$STATE")" = "systemd-boot" ]
  [ "$(jq -r .rpool        "$STATE")" = "rpool" ]
  [ "$(jq -r .swap         "$STATE")" = "true" ]
  [ "$(jq -r .esp_count    "$STATE")" = "2" ]
  [ "$(jq -r '.extras.backup'        "$STATE")" = "false" ]
  [ "$(jq -r '.extras.security'      "$STATE")" = "false" ]
  [ "$(jq -r '.impermanence.enabled' "$STATE")" = "false" ]
  [ "$(jq -r '.impermanence.dataset' "$STATE")" = "rpool/persist" ]
  [ "$(jq -r '.impermanence.mount'   "$STATE")" = "/persist" ]
  [ "$(jq -r '.persist.directories[0]' "$STATE")" = "/etc/wireguard" ]
  [ "$(jq -r '.persist.files[0]'       "$STATE")" = "/etc/foo" ]
}

@test "install_state_write: types — swap/extras/impermanence are booleans" {
  setup_writer_globals
  install_state_write "$STATE"
  [ "$(jq -r '.swap | type'                 "$STATE")" = "boolean" ]
  [ "$(jq -r '.extras.backup | type'        "$STATE")" = "boolean" ]
  [ "$(jq -r '.impermanence.enabled | type' "$STATE")" = "boolean" ]
  [ "$(jq -r '.esp_count | type'            "$STATE")" = "number" ]
  [ "$(jq -r '.persist.directories | type'  "$STATE")" = "array" ]
}

# ── round-trip ───────────────────────────────────────────────────────────────

@test "round-trip: write then load — every schema field intact" {
  setup_writer_globals
  LAYOUT_ESP_PARTS=(/dev/nvme0n1p1 /dev/nvme1n1p1)
  INSTALL_STATE_HOST_JSON='{"persist":{"directories":["/etc/wg"],
    "files":["/etc/foo"]}}'
  install_state_write "$STATE"
  install_state_load  "$STATE"

  [ "$HOSTNAME"             = "box01" ]
  [ "$TIMEZONE"             = "UTC" ]
  [ "$LOCALE"               = "en_US.UTF-8" ]
  [ "$KEYMAP"               = "us" ]
  [ "$KERNEL"               = "lts" ]
  [ "$BOOTLOADER"           = "systemd-boot" ]
  [ "$RPOOL"                = "rpool" ]
  [ "$SWAP"                 = "true" ]
  [ "$ESP_COUNT"            = "2" ]
  [ "$EXTRAS_BACKUP"        = "false" ]
  [ "$EXTRAS_SECURITY"      = "false" ]
  [ "$IMPERMANENCE_ENABLED" = "false" ]
  [ "$IMPERMANENCE_DATASET" = "rpool/persist" ]
  [ "$IMPERMANENCE_MOUNT"   = "/persist" ]
  [ "${#PERSIST_DIRECTORIES[@]}" -eq 1 ]
  [ "${PERSIST_DIRECTORIES[0]}"  = "/etc/wg" ]
  [ "${#PERSIST_FILES[@]}"       -eq 1 ]
  [ "${PERSIST_FILES[0]}"        = "/etc/foo" ]
}

# ── install_state_update ─────────────────────────────────────────────────────

@test "install_state_update: replaces scalar at existing path" {
  valid_state
  install_state_update "$STATE" '.hostname' '"renamed"'
  [ "$(jq -r .hostname "$STATE")" = "renamed" ]
}

@test "install_state_update: creates nested path that did not exist" {
  valid_state
  install_state_update "$STATE" '.secrets.host' '"/tmp/host-secrets.json"'
  [ "$(jq -r .secrets.host "$STATE")" = "/tmp/host-secrets.json" ]
}

@test "install_state_update: sets nested user path under .secrets.users" {
  valid_state
  install_state_update "$STATE" '.secrets.users.alice' '"/tmp/alice.json"'
  [ "$(jq -r .secrets.users.alice "$STATE")" = "/tmp/alice.json" ]
}

@test "install_state_update: preserves untouched fields" {
  valid_state
  install_state_update "$STATE" '.secrets.host' '"/x"'
  [ "$(jq -r .hostname     "$STATE")" = "h" ]
  [ "$(jq -r .timezone     "$STATE")" = "UTC" ]
  [ "$(jq -r '.extras.backup' "$STATE")" = "false" ]
}
