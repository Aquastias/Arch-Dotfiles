#!/usr/bin/env bats
# Tests for .os/lib/packages.sh — collect_packages() logic.
# install_base() is system-bound (pacstrap/reflector) and is not tested here.

setup() {
  TEST_DIR="$(mktemp -d)"
  CONFIG_FILE="$TEST_DIR/install.json"
  export CONFIG_FILE
  GPU_PACMAN_PACKAGES=()
  AUDIO_PACKAGES=()
  # shellcheck source=../lib/common.sh
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  # shellcheck source=../lib/packages.sh
  source "$BATS_TEST_DIRNAME/../lib/packages.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_config() {
  printf '%s\n' "$1" > "$CONFIG_FILE"
}

# ── kernel selection ──────────────────────────────────────────────────────────

@test "collect_packages: lts kernel includes linux-lts" {
  write_config '{"options": {"kernel": "lts"}}'
  run collect_packages
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^linux-lts$"
}

@test "collect_packages: lts kernel includes linux-lts-headers" {
  write_config '{"options": {"kernel": "lts"}}'
  run collect_packages
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^linux-lts-headers$"
}

@test "collect_packages: lts kernel does not include rolling linux" {
  write_config '{"options": {"kernel": "lts"}}'
  run collect_packages
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qx "linux"
}

@test "collect_packages: default kernel includes linux" {
  write_config '{"options": {"kernel": "default"}}'
  run collect_packages
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "linux"
}

@test "collect_packages: default kernel includes linux-headers" {
  write_config '{"options": {"kernel": "default"}}'
  run collect_packages
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^linux-headers$"
}

@test "collect_packages: missing kernel option defaults to lts" {
  write_config '{}'
  run collect_packages
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^linux-lts$"
}

# ── bootloader selection ──────────────────────────────────────────────────────

@test "collect_packages: grub bootloader includes grub" {
  write_config '{"options": {"bootloader": "grub"}}'
  run collect_packages
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^grub$"
}

@test "collect_packages: systemd-boot does not include grub" {
  write_config '{"options": {"bootloader": "systemd-boot"}}'
  run collect_packages
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "^grub$"
}

# ── extra + group packages ────────────────────────────────────────────────────

@test "collect_packages: extra packages appear in output" {
  write_config '{"packages": {"extra": ["htop", "tmux"]}}'
  run collect_packages
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^htop$"
  echo "$output" | grep -q "^tmux$"
}

@test "collect_packages: group packages appear in output" {
  write_config '{"packages": {"groups": {"cli": ["ripgrep", "fd"]}}}'
  run collect_packages
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^ripgrep$"
  echo "$output" | grep -q "^fd$"
}

@test "collect_packages: _ prefixed group keys are filtered out" {
  write_config '{"packages": {"groups": {"_comment": ["fake-pkg"], "cli": ["htop"]}}}'
  run collect_packages
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "^fake-pkg$"
  echo "$output" | grep -q "^htop$"
}

# ── GPU and audio packages ────────────────────────────────────────────────────

@test "collect_packages: GPU_PACMAN_PACKAGES are included" {
  write_config '{}'
  GPU_PACMAN_PACKAGES=(nvidia nvidia-utils)
  run collect_packages
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^nvidia$"
  echo "$output" | grep -q "^nvidia-utils$"
}

@test "collect_packages: AUDIO_PACKAGES are included" {
  write_config '{}'
  AUDIO_PACKAGES=(pipewire pipewire-alsa)
  run collect_packages
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^pipewire$"
  echo "$output" | grep -q "^pipewire-alsa$"
}

# ── deduplication ─────────────────────────────────────────────────────────────

@test "collect_packages: duplicate packages appear only once" {
  write_config '{"packages": {"extra": ["vim"]}}'
  run collect_packages
  [ "$status" -eq 0 ]
  local count
  count="$(echo "$output" | grep -c "^vim$")"
  [ "$count" -eq 1 ]
}

# ── preconditions ─────────────────────────────────────────────────────────────

@test "collect_packages: fails when GPU_PACMAN_PACKAGES is unset" {
  write_config '{}'
  unset GPU_PACMAN_PACKAGES
  run collect_packages
  [ "$status" -ne 0 ]
}

@test "collect_packages: fails when AUDIO_PACKAGES is unset" {
  write_config '{}'
  unset AUDIO_PACKAGES
  run collect_packages
  [ "$status" -ne 0 ]
}
