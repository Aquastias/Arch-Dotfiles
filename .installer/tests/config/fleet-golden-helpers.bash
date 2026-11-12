# fleet-golden-helpers.bash — the Fleet Golden snapshot (ADR 0157).
#
# fleet_golden_snapshot <profile> prints what `install.sh --profile <profile>`
# would install, normalised so an explicit default and an absent one read the
# same: every Install Config schema field through its accessor, the
# non-schema machine facts as sorted JSON, each user's resolved User Profile,
# and the Package Resolver set as source + package (layer provenance dropped,
# so moving a package between layers is not a change).

fleet_golden_snapshot() {
  local profile="$1" installer_directory
  installer_directory="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  INSTALLER_DIR="$installer_directory" bash -c '
    set -euo pipefail
    cd "$INSTALLER_DIR"
    source lib/common.sh
    source lib/config/install-config.sh
    source lib/config/profile-loader.sh
    source lib/packages/package-resolver.sh
    config="$(bash install.sh --profile "$1" --print-config 2>/dev/null)"
    echo "## schema"
    for name in $(install_config_schema_names); do
      printf "%s=%s\n" "$name" \
        "$(install_config_from_json "$config" "$name" | paste -sd,)"
    done
    echo "## machine"
    jq -S "{system, users, post_install, sysctl, persist, mode, ashift,
      os_pool, storage_groups, data_pools}" <<<"$config"
    echo "## users"
    for user in $(jq -r "(.users // [])[]" <<<"$config"); do
      echo "# $user"
      profile_loader_load_user "$user" | jq -S .
    done
    echo "## packages"
    package_resolver_resolve "$(profile_loader_load "$1")" \
      | cut -f1,3 | sort -u
  ' _ "$profile"
}

# fleet_golden_packages <profile> — the package names alone, sorted.
fleet_golden_packages() {
  local _source package
  # Each package row's package, each once.
  while read -r _source package; do
    printf '%s\n' "$package"
  done < <(_fleet_golden_package_rows "$1") | sort -u
}

# _fleet_golden_package_rows <profile> — the snapshot's "<source> <package>"
# rows, after its `## packages` header.
_fleet_golden_package_rows() {
  local line inside=0
  while IFS= read -r line; do
    (( inside )) && printf '%s\n' "$line"
    [[ "$line" == "## packages" ]] && inside=1
  done < <(fleet_golden_snapshot "$1")
  return 0
}

# Laptop-only hardware AUR packages: ADR 0114's one software image covers
# software, not hardware support (ADR 0161).
FLEET_LAPTOP_HARDWARE_PACKAGES=(
  lenovolegionlinux-dkms-git lenovolegionlinux-git
)

# fleet_golden_shared_packages <profile> — fleet_golden_packages minus the
# laptop-only hardware packages: what desktop and laptop must share.
fleet_golden_shared_packages() {
  local source_name package hardware
  # Each package row's package, the laptop-only AUR ones left out.
  while read -r source_name package; do
    for hardware in "${FLEET_LAPTOP_HARDWARE_PACKAGES[@]}"; do
      [[ "$source_name" == aur && "$package" == "$hardware" ]] && continue 2
    done
    printf '%s\n' "$package"
  done < <(_fleet_golden_package_rows "$1") | sort -u
}
