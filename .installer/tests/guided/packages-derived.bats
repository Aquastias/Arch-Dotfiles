#!/usr/bin/env bats
# Tests: derived section (split from packages.bats;
# shared setup in packages-helpers.bash)

load ../lib/json-helpers
load packages-helpers


# ── the read-only derived section (ticket 09) ───────────────────────────────

@test "the derived section lists sources with counts and their origin" {
  printf '%s\n' '{"environment":{"desktop":["kde"],"gpu":["amd"]}}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_package_derived Packages)"
  run guided_controller_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^gpu ▸ [0-9]+   \(from Environment\)'
  echo "$output" | grep -qE '^audio ▸ [0-9]+   \(from Environment\)'
  echo "$output" | grep -qE '^base ▸ [0-9]+'
  echo "$output" | grep -qE '^kernel ▸ [0-9]+   \(from Options\)'
}

@test "origin labels: services + fonts point at their merged homes (ADR 0081)" {
  [ "$(package_resolver_source_origin printing)" = "Daemons" ]
  [ "$(package_resolver_source_origin bluetooth)" = "Daemons" ]
  [ "$(package_resolver_source_origin power)" = "Daemons" ]
  [ "$(package_resolver_source_origin fonts)" = "System" ]
}

@test "the derived section drills to a source's package list" {
  printf '%s\n' '{"environment":{"gpu":["amd"]}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_package_derived Packages)"
  run guided_controller_enter "gpu ▸ 3   (from Environment)"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "pkgderivedsrc" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" source)" = "gpu" ]

  run guided_controller_list
  echo "$output" | grep -q "vulkan-radeon"
}

@test "derived entries cannot be toggled" {
  printf '%s\n' '{"environment":{"gpu":["amd"]}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_package_derived_source Packages gpu)"
  run guided_controller_enter "    vulkan-radeon"
  [ "$output" = "noop" ]
  file_satisfies "$GUIDED_STATE_FILE" '(.packages // "none") == "none"'
}

@test "changing the GPU vendor updates the derived section" {
  printf '%s\n' '{"environment":{"gpu":["amd"]}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_package_derived_source Packages gpu)"
  run guided_controller_list
  echo "$output" | grep -q "vulkan-radeon"
  ! echo "$output" | grep -q "nvidia-open-dkms" || return 1

  printf '%s\n' '{"environment":{"gpu":["nvidia"]}}' > "$GUIDED_STATE_FILE"
  run guided_controller_list
  echo "$output" | grep -q "nvidia-open-dkms"
  ! echo "$output" | grep -q "vulkan-radeon"
}

@test "changing the desktop selection updates the derived section" {
  printf '%s\n' '{"environment":{"desktop":[]}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_package_derived Packages)"
  run guided_controller_list
  ! echo "$output" | grep -qE '^audio ▸' || return 1

  printf '%s\n' '{"environment":{"desktop":["kde"]}}' > "$GUIDED_STATE_FILE"
  run guided_controller_list
  echo "$output" | grep -qE '^audio ▸'
}

@test "toggling a backup tool updates the derived section" {
  printf '%s\n' '{"users":["a"],"post_install":{"backup":{"borg":true}}}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_package_derived Packages)"
  run guided_controller_list
  echo "$output" | grep -qE '^backup ▸ [0-9]+   \(from Backup\)'

  printf '%s\n' '{"users":["a"],"post_install":{"backup":
    {"borg":false,"zfs_auto_snapshot":false}}}' > "$GUIDED_STATE_FILE"
  run guided_controller_list
  ! echo "$output" | grep -qE '^backup ▸'
}

# The section and the CLI inspector share one resolver, so they cannot drift.
@test "the derived section agrees with the Package Resolver" {
  printf '%s\n' '{"environment":{"desktop":["kde"],"gpu":["amd"]}}' \
    > "$GUIDED_STATE_FILE"
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../../lib/packages/package-resolver.sh"

  local effective; effective="$(_controller_effective "$(state)" "$(cat "$GUIDED_BASELINE_FILE")")"
  local direct menu
  local source_name layer package
  direct=""
  # The resolver's gpu-derived packages.
  while IFS=$'\t' read -r source_name layer package; do
    if [[ "$layer" == derived && "$source_name" == gpu ]]; then
      direct+="${package}"$'\n'
    fi
  done < <(package_resolver_resolve "$effective")
  direct="$(printf '%s' "$direct" | sort -u)"
  set_navigation "$(navigation_to_package_derived_source Packages gpu)"
  local row
  menu=""
  # Each listed package, its indent trimmed; the Back row skipped.
  while read -r row; do
    [[ -z "$row" || "$row" == "← Back" ]] || menu+="${row}"$'\n'
  done < <(guided_controller_list)
  [ "$direct" = "$(printf '%s' "$menu" | sort -u)" ]
}
