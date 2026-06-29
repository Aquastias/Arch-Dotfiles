#!/usr/bin/env bats
# Tests for lib/install-state.sh — host↔chroot wire format.

setup() {
  TEST_DIR="$(mktemp -d)"
  STATE="$TEST_DIR/install-state.json"
  # shellcheck source=../lib/install-state.sh
  source "$BATS_TEST_DIRNAME/../lib/install-state.sh"
  # shellcheck source=../lib/config/profile.sh
  source "$BATS_TEST_DIRNAME/../lib/config/profile.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

teardown() { rm -rf "$TEST_DIR"; }

# Full valid state covering every schema field.
valid_state() {
  cat <<'JSON' > "$STATE"
{
  "hostname": "h", "timezone": "UTC",
  "locale": "en_US.UTF-8", "locales": ["en_US.UTF-8"],
  "keymap": "us", "keymaps": ["us"],
  "kernel": "lts", "kernels": ["lts"],
  "bootloader": "systemd-boot",
  "filesystem": "zfs",
  "ssh": { "enabled": false },
  "rpool": "rpool",
  "root_cmdline": "root=ZFS=rpool/ROOT/arch zfs_import_dir=/dev/disk/by-id",
  "hooks": "base udev autodetect modconf block keyboard zfs filesystems",
  "swap": true, "esp_count": 1,
  "zswap": { "enabled": true, "compressor": "zstd", "max_pool_percent": 20 },
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

# ── root filesystem (issue 08) ───────────────────────────────────────────────
# The Chroot Configuration Modules are filesystem-blind; the only discriminator
# they get is .filesystem, which impermanence dispatches on (zfs vs btrfs).

@test "install_state_load: sets FILESYSTEM from .filesystem" {
  valid_state
  set_field '.filesystem' '"btrfs"'
  install_state_load "$STATE"
  [ "$FILESYSTEM" = "btrfs" ]
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

# ── locale/keymap arrays (issue 04) ──────────────────────────────────────────
# Element 0 is the default; the rest are extra generated locales / available
# keyboard layouts. Carried as arrays alongside the scalar primaries.

@test "install_state_load: LOCALES from .locales array" {
  valid_state
  set_field '.locales' '["en_US.UTF-8","de_DE.UTF-8"]'
  install_state_load "$STATE"
  [ "${#LOCALES[@]}" -eq 2 ]
  [ "${LOCALES[0]}" = "en_US.UTF-8" ]
  [ "${LOCALES[1]}" = "de_DE.UTF-8" ]
}

@test "install_state_load: KEYMAPS from .keymaps array" {
  valid_state
  set_field '.keymaps' '["us","de"]'
  install_state_load "$STATE"
  [ "${#KEYMAPS[@]}" -eq 2 ]
  [ "${KEYMAPS[0]}" = "us" ]
  [ "${KEYMAPS[1]}" = "de" ]
}

@test "install_state_load: returns 1 when .locales missing" {
  valid_state
  drop_field '.locales'
  run install_state_load "$STATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *".locales"* ]]
}

@test "install_state_write: emits .locales and .keymaps arrays" {
  setup_writer_globals
  install_state_write "$STATE" "host-a"
  [ "$(jq -r '.locales | type' "$STATE")" = "array" ]
  [ "$(jq -r '.locales[0]'     "$STATE")" = "en_US.UTF-8" ]
  [ "$(jq -r '.keymaps | type' "$STATE")" = "array" ]
  [ "$(jq -r '.keymaps[0]'     "$STATE")" = "us" ]
}

# ── options.ssh.enabled (issue 05) ───────────────────────────────────────────

@test "install_state_load: SSH_ENABLED from .ssh.enabled" {
  valid_state
  set_field '.ssh.enabled' 'true'
  install_state_load "$STATE"
  [ "$SSH_ENABLED" = "true" ]
}

@test "install_state_load: SSH_ENABLED=false preserved" {
  valid_state
  install_state_load "$STATE"
  [ "$SSH_ENABLED" = "false" ]
}

@test "install_state_write: emits .filesystem from install_config_filesystem" {
  setup_writer_globals
  MOCK_FILESYSTEM="btrfs"
  install_state_write "$STATE" "host-a"
  [ "$(jq -r .filesystem "$STATE")" = "btrfs" ]
}

@test "install_state_write: emits .ssh.enabled as a boolean" {
  setup_writer_globals
  install_state_write "$STATE" "host-a"
  [ "$(jq -r '.ssh.enabled | type' "$STATE")" = "boolean" ]
  [ "$(jq -r '.ssh.enabled'        "$STATE")" = "false" ]
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
  drop_field '.ssh.enabled'
  run install_state_load "$STATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *".ssh.enabled"* ]]
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
  install_config_hostname()             { echo "${MOCK_HOSTNAME:-host-a}"; }
  install_config_timezone()             { echo "UTC"; }
  install_config_locale()               { echo "en_US.UTF-8"; }
  install_config_locales()              { echo "en_US.UTF-8"; }
  install_config_keymap()               { echo "us"; }
  install_config_keymaps()              { echo "us"; }
  install_config_kernel()               { echo "lts"; }
  install_config_bootloader()           { echo "systemd-boot"; }
  install_config_filesystem()           { echo "${MOCK_FILESYSTEM:-zfs}"; }
  install_config_ssh_enabled()          { echo "false"; }
  install_config_swap_enabled()         { echo "true"; }
  install_config_zswap_enabled()        { echo "true"; }
  install_config_zswap_compressor()     { echo "zstd"; }
  install_config_zswap_max_pool_percent() { echo "20"; }
  install_config_impermanence_enabled() { echo "false"; }
  install_config_impermanence_dataset() { echo "rpool/persist"; }
  install_config_impermanence_mount()   { echo "/persist"; }
  LAYOUT_OS_POOL_NAME="rpool"
  LAYOUT_ROOT_CMDLINE="root=ZFS=rpool/ROOT/arch zfs_import_dir=/dev/disk/by-id"
  LAYOUT_HOOKS="base udev autodetect modconf block keyboard zfs filesystems"
  LAYOUT_ESP_PARTS=(/dev/nvme0n1p1)
  export OS_DIR="$FIXTURES"
}

@test "install_state_write: .hostname comes from install_config_hostname" {
  setup_writer_globals
  MOCK_HOSTNAME="eterniox"
  install_state_write "$STATE" "host-a"
  [ "$(jq -r .hostname "$STATE")" = "eterniox" ]
}

@test "install_state_write: assembles full schema with nested objects" {
  setup_writer_globals
  LAYOUT_ESP_PARTS=(/dev/nvme0n1p1 /dev/nvme1n1p1)
  install_state_write "$STATE" "host-a"

  [ "$(jq -r .hostname     "$STATE")" = "host-a" ]
  [ "$(jq -r .timezone     "$STATE")" = "UTC" ]
  [ "$(jq -r .locale       "$STATE")" = "en_US.UTF-8" ]
  [ "$(jq -r .keymap       "$STATE")" = "us" ]
  [ "$(jq -r .kernel       "$STATE")" = "lts" ]
  [ "$(jq -r .bootloader   "$STATE")" = "systemd-boot" ]
  [ "$(jq -r .rpool        "$STATE")" = "rpool" ]
  [ "$(jq -r .root_cmdline "$STATE")" = \
    "root=ZFS=rpool/ROOT/arch zfs_import_dir=/dev/disk/by-id" ]
  [ "$(jq -r .hooks        "$STATE")" = \
    "base udev autodetect modconf block keyboard zfs filesystems" ]
  [ "$(jq -r .swap         "$STATE")" = "true" ]
  [ "$(jq -r .esp_count    "$STATE")" = "2" ]
  [ "$(jq -r '.impermanence.enabled' "$STATE")" = "false" ]
  [ "$(jq -r '.impermanence.dataset' "$STATE")" = "rpool/persist" ]
  [ "$(jq -r '.impermanence.mount'   "$STATE")" = "/persist" ]
  [ "$(jq -r '.persist.directories[0]' "$STATE")" = "/etc/wireguard" ]
  [ "$(jq -r '.persist.files[0]'       "$STATE")" = "/etc/foo" ]
  [ "$(jq -r '.zswap.enabled'          "$STATE")" = "true" ]
  [ "$(jq -r '.zswap.compressor'       "$STATE")" = "zstd" ]
  [ "$(jq -r '.zswap.max_pool_percent' "$STATE")" = "20" ]
}

@test "install_state_write: zswap types — enabled bool, percent number" {
  setup_writer_globals
  install_state_write "$STATE" "host-a"
  [ "$(jq -r '.zswap.enabled | type'          "$STATE")" = "boolean" ]
  [ "$(jq -r '.zswap.max_pool_percent | type' "$STATE")" = "number" ]
}

@test "install_state_write: types — swap/extras/impermanence are booleans" {
  setup_writer_globals
  install_state_write "$STATE" "host-a"
  [ "$(jq -r '.swap | type'                 "$STATE")" = "boolean" ]
  [ "$(jq -r '.ssh.enabled | type'          "$STATE")" = "boolean" ]
  [ "$(jq -r '.impermanence.enabled | type' "$STATE")" = "boolean" ]
  [ "$(jq -r '.esp_count | type'            "$STATE")" = "number" ]
  [ "$(jq -r '.persist.directories | type'  "$STATE")" = "array" ]
}

@test "install_state_write: persist empty when host dir absent (fallback)" {
  setup_writer_globals
  export OS_DIR="$TEST_DIR/no-such-os-dir"
  install_state_write "$STATE" "ghost-host"
  [ "$(jq -r '.persist.directories | length' "$STATE")" = "0" ]
  [ "$(jq -r '.persist.files       | length' "$STATE")" = "0" ]
}

@test "install_state_write: core-only host (graceful) writes valid single JSON" {
  # Real-install condition: hosts/core/profile.jsonc EXISTS but the
  # host-specific dir does NOT, so load_profile prints core JSON *and*
  # returns 1. A `|| printf '{}'` fallback then concatenates a second JSON
  # value, corrupting the --argjson persist payload. The state file must
  # remain a single valid JSON document with an empty persist.
  setup_writer_globals
  export OS_DIR="$FIXTURES"   # core present, "ghost-host" absent → rc 1 + stdout
  install_state_write "$STATE" "ghost-host"
  run jq -e . "$STATE"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.persist.directories | length' "$STATE")" = "0" ]
  [ "$(jq -r '.persist.files       | length' "$STATE")" = "0" ]
}

# ── round-trip ───────────────────────────────────────────────────────────────

@test "round-trip: write then load — every schema field intact" {
  setup_writer_globals
  MOCK_HOSTNAME="host-b"
  LAYOUT_ESP_PARTS=(/dev/nvme0n1p1 /dev/nvme1n1p1)
  install_state_write "$STATE" "host-b"
  install_state_load  "$STATE"

  [ "$HOSTNAME"             = "host-b" ]
  [ "$TIMEZONE"             = "UTC" ]
  [ "$LOCALE"               = "en_US.UTF-8" ]
  [ "$KEYMAP"               = "us" ]
  [ "$KERNEL"               = "lts" ]
  [ "$BOOTLOADER"           = "systemd-boot" ]
  [ "$FILESYSTEM"           = "zfs" ]
  [ "$RPOOL"                = "rpool" ]
  [ "$ROOT_CMDLINE"         = \
    "root=ZFS=rpool/ROOT/arch zfs_import_dir=/dev/disk/by-id" ]
  [ "$HOOKS"                = \
    "base udev autodetect modconf block keyboard zfs filesystems" ]
  [ "$SWAP"                 = "true" ]
  [ "$ESP_COUNT"            = "2" ]
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
  [ "$(jq -r '.ssh.enabled' "$STATE")" = "false" ]
}

# ── credential resolution (.secrets / .guided_passwords) ─────────────────────

@test "credential host: returns .secrets.host when set" {
  echo '{"secrets":{"host":"/s/host.json"}}' > "$STATE"
  run install_state_credential_path "$STATE" host
  [ "$status" -eq 0 ]
  [ "$output" = "/s/host.json" ]
}

@test "credential host: falls back to .guided_passwords.host" {
  echo '{"guided_passwords":{"host":"/g/host.json"}}' > "$STATE"
  run install_state_credential_path "$STATE" host
  [ "$output" = "/g/host.json" ]
}

@test "credential host: .secrets wins over .guided_passwords" {
  echo '{"secrets":{"host":"/s/h"},"guided_passwords":{"host":"/g/h"}}' \
    > "$STATE"
  run install_state_credential_path "$STATE" host
  [ "$output" = "/s/h" ]
}

@test "credential user: returns .secrets.users[name]" {
  echo '{"secrets":{"users":{"alice":"/s/a.json"}}}' > "$STATE"
  run install_state_credential_path "$STATE" user alice
  [ "$output" = "/s/a.json" ]
}

@test "credential user: falls back to .guided_passwords.users[name]" {
  echo '{"guided_passwords":{"users":{"alice":"/g/a.json"}}}' > "$STATE"
  run install_state_credential_path "$STATE" user alice
  [ "$output" = "/g/a.json" ]
}

@test "credential: empty output when neither key is set" {
  echo '{}' > "$STATE"
  run install_state_credential_path "$STATE" host
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "credential: empty output when state file is missing" {
  run install_state_credential_path "$TEST_DIR/nope.json" host
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "credential: bad role returns non-zero" {
  echo '{}' > "$STATE"
  run install_state_credential_path "$STATE" bogus
  [ "$status" -ne 0 ]
}

# ── SOPS activation gate (only .secrets.*, never .guided_passwords.*) ─────────

@test "activates_sops: true when .secrets.host set" {
  echo '{"secrets":{"host":"/s/h"}}' > "$STATE"
  run install_state_activates_sops "$STATE"
  [ "$status" -eq 0 ]
}

@test "activates_sops: true when .secrets.users non-empty" {
  echo '{"secrets":{"users":{"alice":"/s/a"}}}' > "$STATE"
  run install_state_activates_sops "$STATE"
  [ "$status" -eq 0 ]
}

@test "activates_sops: false for guided_passwords only (no SOPS)" {
  echo '{"guided_passwords":{"host":"/g/h","users":{"a":"/g/a"}}}' > "$STATE"
  run install_state_activates_sops "$STATE"
  [ "$status" -ne 0 ]
}

@test "activates_sops: false for empty .secrets.users map" {
  echo '{"secrets":{"users":{}}}' > "$STATE"
  run install_state_activates_sops "$STATE"
  [ "$status" -ne 0 ]
}

@test "activates_sops: false when state file is missing" {
  run install_state_activates_sops "$TEST_DIR/nope.json"
  [ "$status" -ne 0 ]
}
