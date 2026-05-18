#!/usr/bin/env bats
# Tests for .os/lib/install-config.sh — typed Install Config accessors.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"

  # Stubs for common.sh output helpers (avoid color/IO at source time).
  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { :; }
  export -f info warn error section

  # shellcheck source=../lib/install-config.sh
  source "$BATS_TEST_DIRNAME/../lib/install-config.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

write_cfg() { printf '%s\n' "$1" > "$CONFIG_FILE"; }

# ── install_config_kernel ─────────────────────────────────────────────────────

@test "install_config_kernel: returns field when present" {
  write_cfg '{"options":{"kernel":"linux"}}'
  run install_config_kernel
  [ "$status" -eq 0 ]
  [ "$output" = "linux" ]
}

@test "install_config_kernel: returns default 'lts' when absent" {
  write_cfg '{"options":{}}'
  run install_config_kernel
  [ "$status" -eq 0 ]
  [ "$output" = "lts" ]
}

# ── install_config_bootloader ────────────────────────────────────────────────

@test "install_config_bootloader: returns field when present" {
  write_cfg '{"options":{"bootloader":"grub"}}'
  run install_config_bootloader
  [ "$status" -eq 0 ]
  [ "$output" = "grub" ]
}

@test "install_config_bootloader: returns default 'systemd-boot' when absent" {
  write_cfg '{"options":{}}'
  run install_config_bootloader
  [ "$status" -eq 0 ]
  [ "$output" = "systemd-boot" ]
}

# ── install_config_swap_enabled ──────────────────────────────────────────────

@test "install_config_swap_enabled: returns field when present" {
  write_cfg '{"options":{"swap":false}}'
  run install_config_swap_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "install_config_swap_enabled: returns default 'true' when absent" {
  write_cfg '{"options":{}}'
  run install_config_swap_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# ── install_config_esp_size ──────────────────────────────────────────────────

@test "install_config_esp_size: returns field when present" {
  write_cfg '{"options":{"esp_size":"1G"}}'
  run install_config_esp_size
  [ "$status" -eq 0 ]
  [ "$output" = "1G" ]
}

@test "install_config_esp_size: returns default '512M' when absent" {
  write_cfg '{"options":{}}'
  run install_config_esp_size
  [ "$status" -eq 0 ]
  [ "$output" = "512M" ]
}

# ── install_config_impermanence_enabled ──────────────────────────────────────

@test "install_config_impermanence_enabled: returns 'true' when set true" {
  write_cfg '{"options":{"impermanence":{"enabled":true}}}'
  run install_config_impermanence_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "install_config_impermanence_enabled: returns 'false' when set false" {
  write_cfg '{"options":{"impermanence":{"enabled":false}}}'
  run install_config_impermanence_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "install_config_impermanence_enabled: returns default 'false' when absent" {
  write_cfg '{"options":{}}'
  run install_config_impermanence_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

# ── install_config_impermanence_dataset ──────────────────────────────────────

@test "install_config_impermanence_dataset: returns field when present" {
  write_cfg '{"options":{"impermanence":{"dataset":"tank/persist"}}}'
  run install_config_impermanence_dataset
  [ "$status" -eq 0 ]
  [ "$output" = "tank/persist" ]
}

@test "install_config_impermanence_dataset: returns default 'rpool/persist' when absent" {
  write_cfg '{"options":{}}'
  run install_config_impermanence_dataset
  [ "$status" -eq 0 ]
  [ "$output" = "rpool/persist" ]
}

# ── install_config_impermanence_mount ────────────────────────────────────────

@test "install_config_impermanence_mount: returns field when present" {
  write_cfg '{"options":{"impermanence":{"mount":"/state"}}}'
  run install_config_impermanence_mount
  [ "$status" -eq 0 ]
  [ "$output" = "/state" ]
}

@test "install_config_impermanence_mount: returns default '/persist' when absent" {
  write_cfg '{"options":{}}'
  run install_config_impermanence_mount
  [ "$status" -eq 0 ]
  [ "$output" = "/persist" ]
}

# ── install_config_age_key_url ───────────────────────────────────────────────

@test "install_config_age_key_url: returns field when present" {
  write_cfg '{"options":{"age_key_url":"https://example.com/key.age"}}'
  run install_config_age_key_url
  [ "$status" -eq 0 ]
  [ "$output" = "https://example.com/key.age" ]
}

@test "install_config_age_key_url: returns empty when absent (no default)" {
  write_cfg '{"options":{}}'
  run install_config_age_key_url
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
