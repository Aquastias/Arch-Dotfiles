#!/usr/bin/env bats
# Tests for lib/install-state.sh — host↔chroot wire format.

load install-state-helpers


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


# ── gpu array (ADR 0053) ─────────────────────────────────────────────────────
# The resolved GPU vendor list (auto → detected vendors) is threaded to the
# chroot so the GPU Configuration Module can decide whether to harden.

@test "install_state_load: GPU from .gpu array" {
  valid_state
  set_field '.gpu' '["amd","nvidia"]'
  install_state_load "$STATE"
  [ "${#GPU[@]}" -eq 2 ]
  [ "${GPU[0]}" = "amd" ]
  [ "${GPU[1]}" = "nvidia" ]
}

@test "install_state_load: GPU single-vendor shape" {
  valid_state
  set_field '.gpu' '["nvidia"]'
  install_state_load "$STATE"
  [ "${#GPU[@]}" -eq 1 ]
  [ "${GPU[0]}" = "nvidia" ]
}

@test "install_state_load: returns 1 when .gpu missing" {
  valid_state
  drop_field '.gpu'
  run install_state_load "$STATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *".gpu"* ]]
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
  [ "$(state_field '.locales | type')" = "array" ]
  [ "$(state_field '.locales[0]')" = "en_US.UTF-8" ]
  [ "$(state_field '.keymaps | type')" = "array" ]
  [ "$(state_field '.keymaps[0]')" = "us" ]
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
  [ "$(state_field .filesystem)" = "btrfs" ]
}

@test "install_state_write: emits .ssh.enabled as a boolean" {
  setup_writer_globals
  install_state_write "$STATE" "host-a"
  [ "$(state_field '.ssh.enabled | type')" = "boolean" ]
  [ "$(state_field '.ssh.enabled')" = "false" ]
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

@test "install_state_write: emits .display_manager from ENVIRONMENT_DISPLAY_MANAGER" {
  setup_writer_globals
  ENVIRONMENT_DISPLAY_MANAGER="greetd"
  install_state_write "$STATE" "host-a"
  [ "$(state_field '.display_manager')" = "greetd" ]
}

@test "install_state_write: .display_manager falls back to none when unset" {
  setup_writer_globals
  unset ENVIRONMENT_DISPLAY_MANAGER
  install_state_write "$STATE" "host-a"
  [ "$(state_field '.display_manager')" = "none" ]
}

@test "install_state_write: emits .gpu array from ENVIRONMENT_GPU" {
  setup_writer_globals
  ENVIRONMENT_GPU=(amd nvidia)
  install_state_write "$STATE" "host-a"
  [ "$(state_field '.gpu | type')" = "array" ]
  [ "$(state_field '.gpu[0]')" = "amd" ]
  [ "$(state_field '.gpu[1]')" = "nvidia" ]
}

@test "install_state_write: emits empty .gpu when ENVIRONMENT_GPU unset" {
  setup_writer_globals
  unset ENVIRONMENT_GPU
  install_state_write "$STATE" "host-a"
  [ "$(state_field '.gpu | type')" = "array" ]
  [ "$(state_field '.gpu | length')" = "0" ]
}

@test "install_state_write: .hostname comes from install_config_hostname" {
  setup_writer_globals
  MOCK_HOSTNAME="eterniox"
  install_state_write "$STATE" "host-a"
  [ "$(state_field .hostname)" = "eterniox" ]
}

@test "install_state_write: assembles full schema with nested objects" {
  setup_writer_globals
  MOCK_PERSIST='{"directories":["/etc/wireguard"],"files":["/etc/foo"]}'
  LAYOUT_ESP_PARTS=(/dev/nvme0n1p1 /dev/nvme1n1p1)
  install_state_write "$STATE" "host-a"

  [ "$(state_field .hostname)" = "host-a" ]
  [ "$(state_field .timezone)" = "UTC" ]
  [ "$(state_field .locale)" = "en_US.UTF-8" ]
  [ "$(state_field .keymap)" = "us" ]
  [ "$(state_field .kernel)" = "lts" ]
  [ "$(state_field .bootloader)" = "systemd-boot" ]
  [ "$(state_field .root_shell)" = "/bin/bash" ]
  [ "$(state_field .rpool)" = "rpool" ]
  [ "$(state_field .root_cmdline)" = \
    "root=ZFS=rpool/ROOT/arch zfs_import_dir=/dev/disk/by-id" ]
  [ "$(state_field .hooks)" = \
    "base udev autodetect modconf block keyboard zfs filesystems" ]
  [ "$(state_field .swap)" = "true" ]
  [ "$(state_field .esp_count)" = "2" ]
  [ "$(state_field '.impermanence.enabled')" = "false" ]
  [ "$(state_field '.impermanence.dataset')" = "rpool/persist" ]
  [ "$(state_field '.impermanence.mount')" = "/persist" ]
  [ "$(state_field '.persist.directories[0]')" = "/etc/wireguard" ]
  [ "$(state_field '.persist.files[0]')" = "/etc/foo" ]
  [ "$(state_field '.zswap.enabled')" = "true" ]
  [ "$(state_field '.zswap.compressor')" = "zstd" ]
  [ "$(state_field '.zswap.max_pool_percent')" = "20" ]
}

@test "install_state_write: zswap types — enabled bool, percent number" {
  setup_writer_globals
  install_state_write "$STATE" "host-a"
  [ "$(state_field '.zswap.enabled | type')" = "boolean" ]
  [ "$(state_field '.zswap.max_pool_percent | type')" = "number" ]
}

@test "install_state_write: zfs.arc_max carries the size (ADR 0161)" {
  setup_writer_globals
  install_config_zfs_arc_max() { echo "4G"; }
  install_state_write "$STATE" "host-a"
  [ "$(state_field '.zfs.arc_max')" = "4G" ]
}

@test "install_state_write: types — swap/extras/impermanence are booleans" {
  setup_writer_globals
  install_state_write "$STATE" "host-a"
  [ "$(state_field '.swap | type')" = "boolean" ]
  [ "$(state_field '.ssh.enabled | type')" = "boolean" ]
  [ "$(state_field '.impermanence.enabled | type')" = "boolean" ]
  [ "$(state_field '.esp_count | type')" = "number" ]
  [ "$(state_field '.persist.directories | type')" = "array" ]
}

@test "install_state_write: persist comes from the effective config" {
  # Not from a profile looked up by name: the installer only knows the
  # hostname (desktop installs eterniox), and Guided adds persist paths to
  # the effective config alone.
  setup_writer_globals
  MOCK_PERSIST='{"directories":["/var/lib/docker"],"files":[]}'
  export INSTALLER_DIR="$TEST_DIR/no-such-os-dir"
  install_state_write "$STATE"
  # The state parses as JSON.
  run jq -e . "$STATE"
  [ "$status" -eq 0 ]
  [ "$(state_field '.persist.directories[0]')" = "/var/lib/docker" ]
  [ "$(state_field '.persist.files | length')" = "0" ]
}


# ── round-trip ───────────────────────────────────────────────────────────────

@test "round-trip: write then load — every schema field intact" {
  setup_writer_globals
  MOCK_PERSIST='{"directories":["/etc/wg"],"files":["/etc/foo"]}'
  MOCK_HOSTNAME="host-b"
  LAYOUT_ESP_PARTS=(/dev/nvme0n1p1 /dev/nvme1n1p1)
  install_state_write "$STATE" "host-b"
  install_state_load  "$STATE"

  [ "$HOSTNAME"             = "host-b" ]
  [ "$TIMEZONE"             = "UTC" ]
  [ "$LOCALE"               = "en_US.UTF-8" ]
  [ "$KEYMAP"               = "us" ]
  [ "$CONSOLE_FONT"         = "default8x16" ]
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
  [ "${#GPU[@]}"                 -eq 2 ]
  [ "${GPU[0]}"                  = "amd" ]
  [ "${GPU[1]}"                  = "nvidia" ]
  [ "$DISPLAY_MANAGER"           = "sddm" ]
}


# ── install_state_update ─────────────────────────────────────────────────────

@test "install_state_update: replaces scalar at existing path" {
  valid_state
  install_state_update "$STATE" '.hostname' '"renamed"'
  [ "$(state_field .hostname)" = "renamed" ]
}

@test "install_state_update: creates nested path that did not exist" {
  valid_state
  install_state_update "$STATE" '.secrets.host' '"/tmp/host-secrets.json"'
  [ "$(state_field .secrets.host)" = "/tmp/host-secrets.json" ]
}

@test "install_state_update: sets nested user path under .secrets.users" {
  valid_state
  install_state_update "$STATE" '.secrets.users.alice' '"/tmp/alice.json"'
  [ "$(state_field .secrets.users.alice)" = "/tmp/alice.json" ]
}

@test "install_state_update: preserves untouched fields" {
  valid_state
  install_state_update "$STATE" '.secrets.host' '"/x"'
  [ "$(state_field .hostname)" = "h" ]
  [ "$(state_field .timezone)" = "UTC" ]
  [ "$(state_field '.ssh.enabled')" = "false" ]
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

@test "install_state_write: .apparmor carries the Security Extras selection" {
  setup_writer_globals
  install_state_write "$STATE" "host-a"
  [ "$(state_field '.apparmor | type')" = "boolean" ]
  [ "$(state_field '.apparmor')" = "true" ]
  MOCK_APPARMOR=false install_state_write "$STATE" "host-a"
  [ "$(state_field '.apparmor')" = "false" ]
}
