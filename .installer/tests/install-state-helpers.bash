# install-state-helpers.bash — shared setup for the install-state-*.bats parts
# Tests for lib/install-state.sh — host↔chroot wire format.

setup() {
  TEST_DIR="$(mktemp -d)"
  STATE="$TEST_DIR/install-state.json"
  # shellcheck source=../lib/install-state.sh
  source "$BATS_TEST_DIRNAME/../lib/install-state.sh"
  # shellcheck source=../lib/config/profile-loader.sh
  source "$BATS_TEST_DIRNAME/../lib/config/profile-loader.sh"
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
  "console_font": "default8x16",
  "kernel": "lts", "kernels": ["lts"],
  "bootloader": "systemd-boot",
  "root_shell": "/bin/bash",
  "filesystem": "zfs",
  "ssh": { "enabled": false },
  "rpool": "rpool",
  "root_cmdline": "root=ZFS=rpool/ROOT/arch zfs_import_dir=/dev/disk/by-id",
  "hooks": "base udev autodetect modconf block keyboard zfs filesystems",
  "gpu": ["amd", "nvidia"],
  "display_manager": "sddm",
  "swap": true, "esp_count": 1,
  "zswap": { "enabled": true, "compressor": "zstd", "max_pool_percent": 20 },
  "impermanence": { "enabled": false, "dataset": "rpool/persist",
                    "mount": "/persist" },
  "persist":      { "directories": [], "files": [] }
}
JSON
}

drop_field() {
  local path="$1" temporary_file
  temporary_file="$(mktemp)"
  jq "del($path)" "$STATE" > "$temporary_file" && mv "$temporary_file" "$STATE"
}

set_field() {
  local path="$1" value="$2" temporary_file
  temporary_file="$(mktemp)"
  jq "$path = $value" "$STATE" > "$temporary_file" && mv "$temporary_file" "$STATE"
}

setup_writer_globals() {
  install_config_hostname()             { echo "${MOCK_HOSTNAME:-host-a}"; }
  install_config_timezone()             { echo "UTC"; }
  install_config_locale()               { echo "en_US.UTF-8"; }
  install_config_locales()              { echo "en_US.UTF-8"; }
  install_config_keymap()               { echo "us"; }
  install_config_keymaps()              { echo "us"; }
  install_config_console_font()         { echo "default8x16"; }
  install_config_kernel()               { echo "lts"; }
  install_config_bootloader()           { echo "systemd-boot"; }
  install_config_root_shell()          { echo "${MOCK_ROOT_SHELL:-/bin/bash}"; }
  install_config_filesystem()           { echo "${MOCK_FILESYSTEM:-zfs}"; }
  install_config_ssh_enabled()          { echo "false"; }
  install_config_swap_enabled()         { echo "true"; }
  install_config_zswap_enabled()        { echo "true"; }
  install_config_zswap_compressor()     { echo "zstd"; }
  install_config_zswap_max_pool_percent() { echo "20"; }
  install_config_impermanence_enabled() { echo "false"; }
  install_config_impermanence_dataset() { echo "rpool/persist"; }
  install_config_impermanence_mount()   { echo "/persist"; }
  install_config_apparmor_enabled()     { echo "${MOCK_APPARMOR:-true}"; }
  LAYOUT_OS_POOL_NAME="rpool"
  LAYOUT_ROOT_CMDLINE="root=ZFS=rpool/ROOT/arch zfs_import_dir=/dev/disk/by-id"
  LAYOUT_HOOKS="base udev autodetect modconf block keyboard zfs filesystems"
  LAYOUT_ESP_PARTS=(/dev/nvme0n1p1)
  ENVIRONMENT_GPU=(amd nvidia)
  ENVIRONMENT_DISPLAY_MANAGER="sddm"
  export INSTALLER_DIR="$FIXTURES"
}

