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

# assert_single_disk_skeleton <host> — a single-mode host (VM or bare-metal)
# carries only mode:single (the disk is operator-picked); no os_pool/disk
# fields, no host_profile, and the whole thing validates closed-schema clean.
assert_single_disk_skeleton() {
  local host="$1" j
  j="$(load_profile "$host")"
  echo "$j" | jq -e '.mode == "single"'
  echo "$j" | jq -e '(has("disk")) | not'
  echo "$j" | jq -e '(has("os_pool")) | not'
  echo "$j" | jq -e 'has("host_profile") | not'
  run validate_config_schema host "$j"
  [ "$status" -eq 0 ]
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

# ── single-mode VM hosts: skeleton is just mode:single (disk picked) ─────────
# arch-kde/-hyprland/-kde-hyprland differ only in environment.desktop. The
# skeleton carries no os_pool/storage_groups/data_pools — single mode
# auto-partitions one operator-picked disk (ESP + rpool + dpool).

@test "migration: arch-kde preserves legacy software + single-mode skeleton" {
  assert_software_preserved arch-kde
  assert_single_disk_skeleton arch-kde
  load_profile arch-kde | jq -e '.environment.desktop == "kde"'
}

@test "migration: arch-hyprland preserves legacy software + single skeleton" {
  assert_software_preserved arch-hyprland
  assert_single_disk_skeleton arch-hyprland
  load_profile arch-hyprland | jq -e '.environment.desktop == "hyprland"'
}

@test "migration: arch-kde-hyprland preserves legacy software + single skel" {
  assert_software_preserved arch-kde-hyprland
  assert_single_disk_skeleton arch-kde-hyprland
  load_profile arch-kde-hyprland \
    | jq -e '.environment.desktop == ["kde", "hyprland"]'
}

# arch-secure pins a 2-disk OS mirror and the combined secure feature set
# (SOPS via age_key_url + impermanence + ZFS encryption). Those machine
# options are outside the software projection, so the guard asserts them by
# shape to catch an accidental drop.
@test "migration: arch-secure preserves software + secure multi-mirror skel" {
  assert_software_preserved arch-secure

  local j
  j="$(load_profile arch-secure)"
  echo "$j" | jq -e '.mode == "multi"'
  echo "$j" | jq -e '.os_pool.pool_name == "rpool"'
  echo "$j" | jq -e '.os_pool.topology == "mirror"'
  echo "$j" | jq -e '(.os_pool | has("disks")) | not'
  echo "$j" | jq -e '.storage_groups == []'
  echo "$j" | jq -e '.data_pools == []'
  echo "$j" | jq -e '.options.encryption == true'
  echo "$j" | jq -e '.options.impermanence.enabled == true'
  echo "$j" | jq -e '.options.age_key_url != ""'
  echo "$j" | jq -e '.users == ["vm-test"]'
  echo "$j" | jq -e 'has("host_profile") | not'

  run validate_config_schema host "$j"
  [ "$status" -eq 0 ]
}

# laptop (chronos): bare-metal single-disk host with a pinned hostname and the
# kde+hyprland desktop. Its big package list rides the software equivalence.
@test "migration: laptop preserves legacy software + single-disk skeleton" {
  assert_software_preserved laptop
  assert_single_disk_skeleton laptop

  local j
  j="$(load_profile laptop)"
  echo "$j" | jq -e '.system.hostname == "chronos"'
  echo "$j" | jq -e '.environment.desktop == ["kde", "hyprland"]'
}

# ── users: profile.jsonc must reproduce the legacy user config exactly ──────
# A user profile is pure software, so the guard is full equivalence between
# load_user_config (legacy) and load_user_profile (new). The migrated file
# existing is the discriminator — without it load_user_profile falls back to
# the legacy config and the equivalence would pass vacuously.

# assert_user_migrated <name> — the user is on profile.jsonc (merged under
# users/core/profile.jsonc) and reproduces the legacy load_user_config
# exactly, validating clean.
assert_user_migrated() {
  local name="$1" legacy new
  [ -f "$OS_DIR/users/core/profile.jsonc" ]
  [ -f "$OS_DIR/users/${name}/profile.jsonc" ]

  legacy="$(load_user_config "$name" | jq -S '.')"
  new="$(load_user_profile "$name" | jq -S '.')"
  [ "$legacy" = "$new" ] || {
    echo "user drift for ${name}:"
    diff <(echo "$legacy") <(echo "$new")
    return 1
  }

  run validate_config_schema user "$new"
  [ "$status" -eq 0 ]
}

@test "migration: aquastias user is on profile.jsonc, preserving legacy config" {
  assert_user_migrated aquastias
}

@test "migration: vm-data user is on profile.jsonc, preserving legacy config" {
  assert_user_migrated vm-data
}

@test "migration: vm-test user is on profile.jsonc, preserving legacy config" {
  assert_user_migrated vm-test
}
