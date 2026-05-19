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

# ── install_config_hostname ──────────────────────────────────────────────────

@test "install_config_hostname: returns field when present" {
  write_cfg '{"system":{"hostname":"laptop"}}'
  run install_config_hostname
  [ "$status" -eq 0 ]
  [ "$output" = "laptop" ]
}

@test "install_config_hostname: returns empty when absent (no default)" {
  write_cfg '{"system":{}}'
  run install_config_hostname
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── install_config_locale ────────────────────────────────────────────────────

@test "install_config_locale: returns field when present" {
  write_cfg '{"system":{"locale":"fr_FR.UTF-8"}}'
  run install_config_locale
  [ "$status" -eq 0 ]
  [ "$output" = "fr_FR.UTF-8" ]
}

@test "install_config_locale: returns default 'en_US.UTF-8' when absent" {
  write_cfg '{"system":{}}'
  run install_config_locale
  [ "$status" -eq 0 ]
  [ "$output" = "en_US.UTF-8" ]
}

# ── install_config_timezone ──────────────────────────────────────────────────

@test "install_config_timezone: returns field when present" {
  write_cfg '{"system":{"timezone":"Europe/Paris"}}'
  run install_config_timezone
  [ "$status" -eq 0 ]
  [ "$output" = "Europe/Paris" ]
}

@test "install_config_timezone: returns default 'UTC' when absent" {
  write_cfg '{"system":{}}'
  run install_config_timezone
  [ "$status" -eq 0 ]
  [ "$output" = "UTC" ]
}

# ── install_config_keymap ────────────────────────────────────────────────────

@test "install_config_keymap: returns field when present" {
  write_cfg '{"system":{"keymap":"de"}}'
  run install_config_keymap
  [ "$status" -eq 0 ]
  [ "$output" = "de" ]
}

@test "install_config_keymap: returns default 'us' when absent" {
  write_cfg '{"system":{}}'
  run install_config_keymap
  [ "$status" -eq 0 ]
  [ "$output" = "us" ]
}

# ── install_config_desktop ───────────────────────────────────────────────────

@test "install_config_desktop: string yields one line" {
  write_cfg '{"environment":{"desktop":"kde"}}'
  run install_config_desktop
  [ "$status" -eq 0 ]
  [ "$output" = "kde" ]
}

@test "install_config_desktop: array yields one line per element" {
  write_cfg '{"environment":{"desktop":["kde","hyprland"]}}'
  run install_config_desktop
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "kde" ]
  [ "${lines[1]}" = "hyprland" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "install_config_desktop: null yields empty" {
  write_cfg '{"environment":{"desktop":null}}'
  run install_config_desktop
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "install_config_desktop: absent yields empty" {
  write_cfg '{"environment":{}}'
  run install_config_desktop
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── install_config_gpu ───────────────────────────────────────────────────────

@test "install_config_gpu: string yields one line" {
  write_cfg '{"environment":{"gpu":"amd"}}'
  run install_config_gpu
  [ "$status" -eq 0 ]
  [ "$output" = "amd" ]
}

@test "install_config_gpu: array yields one line per element" {
  write_cfg '{"environment":{"gpu":["amd","nvidia"]}}'
  run install_config_gpu
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "amd" ]
  [ "${lines[1]}" = "nvidia" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "install_config_gpu: null yields default 'auto'" {
  write_cfg '{"environment":{"gpu":null}}'
  run install_config_gpu
  [ "$status" -eq 0 ]
  [ "$output" = "auto" ]
}

@test "install_config_gpu: absent yields default 'auto'" {
  write_cfg '{"environment":{}}'
  run install_config_gpu
  [ "$status" -eq 0 ]
  [ "$output" = "auto" ]
}

# ── install_config_extras_backup ─────────────────────────────────────────────

@test "install_config_extras_backup: returns 'true' when set true" {
  write_cfg '{"post_install":{"backup":true}}'
  run install_config_extras_backup
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "install_config_extras_backup: returns 'false' when set false" {
  write_cfg '{"post_install":{"backup":false}}'
  run install_config_extras_backup
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "install_config_extras_backup: returns default 'false' when absent" {
  write_cfg '{"post_install":{}}'
  run install_config_extras_backup
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

# ── install_config_extras_security ───────────────────────────────────────────

@test "install_config_extras_security: returns 'true' when set true" {
  write_cfg '{"post_install":{"security":true}}'
  run install_config_extras_security
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "install_config_extras_security: returns 'false' when set false" {
  write_cfg '{"post_install":{"security":false}}'
  run install_config_extras_security
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "install_config_extras_security: returns default 'false' when absent" {
  write_cfg '{"post_install":{}}'
  run install_config_extras_security
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

# ── install_config_packages_extra ────────────────────────────────────────────

@test "install_config_packages_extra: array yields one line per element" {
  write_cfg '{"packages":{"extra":["firefox","vlc"]}}'
  run install_config_packages_extra
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "firefox" ]
  [ "${lines[1]}" = "vlc" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "install_config_packages_extra: empty array yields empty" {
  write_cfg '{"packages":{"extra":[]}}'
  run install_config_packages_extra
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "install_config_packages_extra: absent yields empty" {
  write_cfg '{"packages":{}}'
  run install_config_packages_extra
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── install_config_packages_groups ───────────────────────────────────────────

@test "install_config_packages_groups: flattens all groups into one list" {
  write_cfg '{"packages":{"groups":{"dev":["git","vim"],"media":["mpv"]}}}'
  run install_config_packages_groups
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "install_config_packages_groups: skips _-prefixed keys" {
  write_cfg '{"packages":{"groups":{"_comment":["ignored"],"dev":["git"]}}}'
  run install_config_packages_groups
  [ "$status" -eq 0 ]
  [ "$output" = "git" ]
}

@test "install_config_packages_groups: skips non-array values" {
  write_cfg '{"packages":{"groups":{"bogus":"oops","dev":["git"]}}}'
  run install_config_packages_groups
  [ "$status" -eq 0 ]
  [ "$output" = "git" ]
}

@test "install_config_packages_groups: absent yields empty" {
  write_cfg '{"packages":{}}'
  run install_config_packages_groups
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── install_config_dotfiles_repo ─────────────────────────────────────────────

@test "install_config_dotfiles_repo: returns field when present" {
  write_cfg '{"dotfiles_repo":"https://github.com/u/dotfiles"}'
  run install_config_dotfiles_repo
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/u/dotfiles" ]
}

@test "install_config_dotfiles_repo: returns empty when absent (no default)" {
  write_cfg '{}'
  run install_config_dotfiles_repo
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── install_config_os_pool_name ──────────────────────────────────────────────

@test "install_config_os_pool_name: returns field when present" {
  write_cfg '{"os_pool_name":"tank"}'
  run install_config_os_pool_name
  [ "$status" -eq 0 ]
  [ "$output" = "tank" ]
}

@test "install_config_os_pool_name: returns default 'rpool' when absent" {
  write_cfg '{}'
  run install_config_os_pool_name
  [ "$status" -eq 0 ]
  [ "$output" = "rpool" ]
}

# ── install_config_storage_pool_name ─────────────────────────────────────────

@test "install_config_storage_pool_name: returns field when present" {
  write_cfg '{"storage_pool_name":"tank"}'
  run install_config_storage_pool_name
  [ "$status" -eq 0 ]
  [ "$output" = "tank" ]
}

@test "install_config_storage_pool_name: returns default 'dpool' when absent" {
  write_cfg '{}'
  run install_config_storage_pool_name
  [ "$status" -eq 0 ]
  [ "$output" = "dpool" ]
}

# ── install_config_storage_mount ─────────────────────────────────────────────

@test "install_config_storage_mount: returns field when present" {
  write_cfg '{"storage_mount":"/srv"}'
  run install_config_storage_mount
  [ "$status" -eq 0 ]
  [ "$output" = "/srv" ]
}

@test "install_config_storage_mount: returns default '/data' when absent" {
  write_cfg '{}'
  run install_config_storage_mount
  [ "$status" -eq 0 ]
  [ "$output" = "/data" ]
}

# ── install_config_ashift ────────────────────────────────────────────────────

@test "install_config_ashift: returns field when present" {
  write_cfg '{"ashift":13}'
  run install_config_ashift
  [ "$status" -eq 0 ]
  [ "$output" = "13" ]
}

@test "install_config_ashift: returns default '12' when absent" {
  write_cfg '{}'
  run install_config_ashift
  [ "$status" -eq 0 ]
  [ "$output" = "12" ]
}

# ── install_config_os_pool_ashift ────────────────────────────────────────────

@test "install_config_os_pool_ashift: returns field when present" {
  write_cfg '{"os_pool":{"ashift":12}}'
  run install_config_os_pool_ashift
  [ "$status" -eq 0 ]
  [ "$output" = "12" ]
}

@test "install_config_os_pool_ashift: returns default '13' when absent" {
  write_cfg '{"os_pool":{}}'
  run install_config_os_pool_ashift
  [ "$status" -eq 0 ]
  [ "$output" = "13" ]
}

# ── install_config_storage_group_ashift ──────────────────────────────────────

@test "install_config_storage_group_ashift: returns field for given index" {
  write_cfg '{"storage_groups":[{"ashift":9},{"ashift":13}]}'
  run install_config_storage_group_ashift 1
  [ "$status" -eq 0 ]
  [ "$output" = "13" ]
}

@test "install_config_storage_group_ashift: returns default '12' when absent" {
  write_cfg '{"storage_groups":[{}]}'
  run install_config_storage_group_ashift 0
  [ "$status" -eq 0 ]
  [ "$output" = "12" ]
}

# ── install_config_encryption_enabled ────────────────────────────────────────

@test "install_config_encryption_enabled: returns 'true' when set true" {
  write_cfg '{"options":{"encryption":true}}'
  run install_config_encryption_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "install_config_encryption_enabled: returns 'false' when set false" {
  write_cfg '{"options":{"encryption":false}}'
  run install_config_encryption_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "install_config_encryption_enabled: returns default 'false' when absent" {
  write_cfg '{"options":{}}'
  run install_config_encryption_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}
