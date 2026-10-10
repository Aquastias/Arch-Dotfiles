#!/usr/bin/env bats
# Tests for .installer/lib/packages/package-list.sh — package_list_collect()
# logic. package_list_install_base() is system-bound (pacstrap/reflector) and is
# not tested here.

setup() {
  TEST_DIR="$(mktemp -d)"
  CONFIG_FILE="$TEST_DIR/install.json"
  export CONFIG_FILE
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/install-config.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/install-config.sh"
  # shellcheck source=../../lib/packages/package-list.sh
  source "$BATS_TEST_DIRNAME/../../lib/packages/package-list.sh"
  # shellcheck source=../../lib/config/environment.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/environment.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_config() {
  printf '%s\n' "$1" > "$CONFIG_FILE"
}

# ── kernel selection ──────────────────────────────────────────────────────────

@test "package_list_collect: lts kernel includes linux-lts" {
  write_config '{"options": {"kernel": "lts"}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^linux-lts$"
}

@test "package_list_collect: lts kernel includes linux-lts-headers" {
  write_config '{"options": {"kernel": "lts"}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^linux-lts-headers$"
}

@test "package_list_collect: lts kernel does not include rolling linux" {
  write_config '{"options": {"kernel": "lts"}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qx "linux"
}

@test "package_list_collect: default kernel includes linux" {
  write_config '{"options": {"kernel": "default"}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "linux"
}

@test "package_list_collect: default kernel includes linux-headers" {
  write_config '{"options": {"kernel": "default"}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^linux-headers$"
}

@test "package_list_collect: missing kernel option defaults to lts" {
  write_config '{}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^linux-lts$"
}

@test "package_list_collect: two-token list installs both kernels and headers" {
  write_config '{"options":{"kernel":["default","lts"]}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "linux"
  echo "$output" | grep -qx "linux-headers"
  echo "$output" | grep -qx "linux-lts"
  echo "$output" | grep -qx "linux-lts-headers"
}

@test "package_list_collect: zfs-dkms appears exactly once for a multi-kernel list" {
  write_config '{"options":{"kernel":["default","lts"]}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -cx "zfs-dkms")" -eq 1 ]
}

@test "package_list_collect: a pure ext4 root pulls no ZFS userland (ADR 0043)" {
  write_config '{"filesystem":"ext4","options":{"kernel":"lts"}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qx "zfs-dkms"
  ! echo "$output" | grep -qx "zfs-utils"
}

# ── bootloader selection ──────────────────────────────────────────────────────

@test "package_list_collect: grub bootloader includes grub" {
  write_config '{"options": {"bootloader": "grub"}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^grub$"
}

@test "package_list_collect: systemd-boot does not include grub" {
  write_config '{"options": {"bootloader": "systemd-boot"}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "^grub$"
}

# ── multilib gate (issue 06): options.multilib=false skips enabling ─────────
# The enable path is system-bound (greps the host /etc/pacman.conf); only the
# new config gate is unit-tested — it must short-circuit before any file touch.

@test "pacman_config_enable_optional_repositories: an empty set skips enabling" {
  write_config '{"options":{"optional_repos":[]}}'
  run pacman_config_enable_optional_repositories
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "no optional repositories"
}

@test "install_config_optional_repos: defaults to multilib when unset" {
  write_config '{"options":{}}'
  run install_config_optional_repos
  [ "$status" -eq 0 ]
  [ "$output" == "multilib" ]
}

@test "_pacman_config_custom_repository_siglevel: builds the pacman SigLevel value" {
  [ "$(_pacman_config_custom_repository_siglevel Never TrustAll)" == "Never" ]
  [ "$(_pacman_config_custom_repository_siglevel Optional TrustAll)" == "Optional TrustAll" ]
  [ "$(_pacman_config_custom_repository_siglevel Required TrustedOnly)" == "Required TrustedOnly" ]
  [ "$(_pacman_config_custom_repository_siglevel '' '')" == "Required TrustedOnly" ]
}

# ── reflector country args (issue 06): mirror_countries → --country ───────── A
# pure helper so package_list_install_base (system-bound) stays untested while
# the arg construction is covered. reflector takes a comma-separated --country
# value.

@test "package_list_reflector_country_arguments: default five become one --country list" {
  write_config '{}'
  run package_list_reflector_country_arguments
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "--country" ]
  [ "${lines[1]}" = "Germany,Switzerland,Sweden,France,Romania" ]
}

@test "package_list_reflector_country_arguments: an explicit list is joined in order" {
  write_config '{"options":{"mirror_countries":["Japan","Australia"]}}'
  run package_list_reflector_country_arguments
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "--country" ]
  [ "${lines[1]}" = "Japan,Australia" ]
}

# ── repo packages (the one authored repo slot) ────────────────────────────────

@test "package_list_collect: repo category packages appear in output" {
  write_config '{"packages": {"repo": {"cli": ["ripgrep", "fd"]}}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^ripgrep$"
  echo "$output" | grep -q "^fd$"
}

@test "package_list_collect: every repo category is flattened in" {
  write_config \
    '{"packages": {"repo": {"cli": ["htop"], "media": ["vlc"]}}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^htop$"
  echo "$output" | grep -q "^vlc$"
}

# The guided extra-packages row writes packages.repo.extra into the Effective
# Config; package_list_collect reads it from there, so a typed name installs on
# every front-end (no hosts/<hostname>/ re-read required).
@test "package_list_collect: the guided extra-packages category installs" {
  write_config '{"packages": {"repo": {"extra": ["htop", "tmux"]}}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^htop$"
  echo "$output" | grep -q "^tmux$"
}

@test "package_list_collect: absent packages block is fine" {
  write_config '{}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^base$"
}

# stow joined the Base Package List: the Runner stows dotfiles for every user
# unconditionally, but no layer guaranteed the binary (R1).
@test "package_list_collect: stow is in the Base Package List" {
  write_config '{}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "stow"
}

# ── archzfs LTS ceiling pin wiring (ADR 0137) ─────────────────────────────────
# package_list_collect reads LTS_PIN_SPECS (exported by
# archzfs_kernel_lts_pin_prepare) and swaps the bare lts token + headers for the
# version-pinned specs.

@test "package_list_collect: LTS_PIN_SPECS swaps the bare lts token + headers" {
  write_config '{"options": {"kernel": "lts"}}'
  LTS_PIN_SPECS="linux-lts=6.18.52-1 linux-lts-headers=6.18.52-1" \
    run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "linux-lts=6.18.52-1"
  echo "$output" | grep -qx "linux-lts-headers=6.18.52-1"
  # the bare, unpinned tokens must be gone
  ! echo "$output" | grep -qx "linux-lts"
  ! echo "$output" | grep -qx "linux-lts-headers"
}

@test "package_list_collect: no LTS_PIN_SPECS → bare tokens survive (byte-identical)" {
  write_config '{"options": {"kernel": "lts"}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "linux-lts"
  echo "$output" | grep -qx "linux-lts-headers"
  ! echo "$output" | grep -q "linux-lts="
}

@test "package_list_collect: LTS pin leaves a non-lts flavour untouched" {
  write_config '{"options": {"kernel": ["lts", "default"]}}'
  LTS_PIN_SPECS="linux-lts=6.18.52-1 linux-lts-headers=6.18.52-1" \
    run package_list_collect
  [ "$status" -eq 0 ]
  # the rolling kernel + headers are never rewritten
  echo "$output" | grep -qx "linux"
  echo "$output" | grep -qx "linux-headers"
  echo "$output" | grep -qx "linux-lts=6.18.52-1"
}

# ── GPU and audio packages ────────────────────────────────────────────────────

@test "package_list_collect: environment.gpu=nvidia drivers appear in output" {
  write_config '{"environment": {"gpu": "nvidia"}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^nvidia-open-dkms$"
  echo "$output" | grep -q "^nvidia-utils$"
}

@test "package_list_collect: environment.desktop=kde pulls pipewire" {
  write_config '{"environment": {"desktop": "kde", "gpu": "nvidia"}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^pipewire$"
  echo "$output" | grep -q "^wireplumber$"
  # pipewire's optdepend for realtime scheduling; absent, every PipeWire
  # client logs "mod.rt: RTKit error" (Audit Run 20261002)
  echo "$output" | grep -q "^rtkit$"
}

# ── universal infrastructure ──────────────────────────────────────────────────

@test "package_list_collect: base set includes cronie" {
  write_config '{}'
  run package_list_collect
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "cronie"
}

# ── deduplication ─────────────────────────────────────────────────────────────

@test "package_list_collect: duplicate packages appear only once" {
  write_config '{"packages": {"extra": ["vim"]}}'
  run package_list_collect
  [ "$status" -eq 0 ]
  local count
  count="$(echo "$output" | grep -c "^vim$")"
  [ "$count" -eq 1 ]
}
