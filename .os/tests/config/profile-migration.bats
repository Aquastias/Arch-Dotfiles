#!/usr/bin/env bats
# Migration equivalence guard (ADR 0036, issue unified-host-profile/09).
#
# While the legacy install.template.jsonc + config.jsonc coexist with the
# new profile.jsonc (both removed in the big-bang cleanup, issue 10), each
# migrated host must:
#   (a) preserve the legacy effective *software* byte-for-byte
#       (users/system_programs/sysctl/packages/persist/post_install),
#   (b) carry the device-free machine skeleton (os_pool/storage_groups/
#       data_pools topology, no disks), and
#   (c) validate clean against the closed schema, with no host_profile.
#
# Machine/layout fields are intentionally restructured (flat install.jsonc
# scalars -> structured os_pool skeleton), so they are asserted by shape,
# not by equivalence. This whole file is deleted in issue 10.

setup() {
  OS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export OS_DIR

  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { :; }
  export -f info warn error section

  # shellcheck source=../../lib/config/profile.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/profile.sh"
}

# The software the migrated profile must reproduce from the legacy synthesis.
SOFTWARE='{users,system_programs,sysctl,packages,persist,post_install}'

# assert_software_preserved <host> — the legacy synthesis (template + config)
# and the new profile.jsonc merge must agree on every software field.
assert_software_preserved() {
  local host="$1" legacy new
  legacy="$(_load_profile_synthesize "$host" | jq -S "$SOFTWARE")"
  new="$(load_profile "$host" | jq -S "$SOFTWARE")"
  [ "$legacy" = "$new" ] || {
    echo "software drift for ${host}:"
    diff <(echo "$legacy") <(echo "$new")
    return 1
  }
}

@test "migration: desktop preserves legacy software + device-free skeleton" {
  assert_software_preserved desktop

  local j
  j="$(load_profile desktop)"
  echo "$j" | jq -e '.mode == "multi"'
  echo "$j" | jq -e '.os_pool.pool_name == "rpool"'
  echo "$j" | jq -e '.os_pool.topology == "mirror"'
  echo "$j" | jq -e '(.os_pool | has("disks")) | not'
  echo "$j" | jq -e '[.storage_groups[] | .name] == ["data"]'
  echo "$j" | jq -e '.storage_groups[0].topology == "raidz1"'
  echo "$j" | jq -e '.storage_groups[0].mount == "/data"'
  echo "$j" | jq -e '([.storage_groups[] | has("disks")] | any) | not'
  echo "$j" | jq -e '.data_pools == []'
  echo "$j" | jq -e '.system.hostname == "eterniox"'
  echo "$j" | jq -e '.environment.desktop == ["kde", "hyprland"]'
  echo "$j" | jq -e 'has("host_profile") | not'

  run validate_config_schema host "$j"
  [ "$status" -eq 0 ]
}

# ── users: profile.jsonc must reproduce the legacy user config exactly ──────
# A user profile is pure software, so the guard is full equivalence between
# load_user_config (legacy) and load_user_profile (new). The migrated file
# existing is the discriminator — without it load_user_profile falls back to
# the legacy config and the equivalence would pass vacuously.

@test "migration: aquastias user is on profile.jsonc, preserving legacy config" {
  [ -f "$OS_DIR/users/core/profile.jsonc" ]
  [ -f "$OS_DIR/users/aquastias/profile.jsonc" ]

  local legacy new
  legacy="$(load_user_config aquastias | jq -S '.')"
  new="$(load_user_profile aquastias | jq -S '.')"
  [ "$legacy" = "$new" ] || {
    echo "user drift for aquastias:"
    diff <(echo "$legacy") <(echo "$new")
    return 1
  }

  run validate_config_schema user "$new"
  [ "$status" -eq 0 ]
}
