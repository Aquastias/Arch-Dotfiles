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
      | awk -F "\t" "{ print \$1 \"\t\" \$3 }" | sort -u
  ' _ "$profile"
}

# fleet_golden_packages <profile> — the package names alone, sorted.
fleet_golden_packages() {
  fleet_golden_snapshot "$1" \
    | awk '/^## packages$/ { on = 1; next } on { print $2 }' | sort -u
}
