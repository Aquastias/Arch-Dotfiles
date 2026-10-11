#!/usr/bin/env bats
# Tests: closed-schema validation (split from profile-loader.bats;
# shared setup in profile-loader-helpers.bash)

load profile-loader-helpers


# ── completeness: every real authored config validates clean ───────────────
# The forcing function — the schema must enumerate every key the live repo
# uses, or these break (and so would a real install).

@test "real: every host profile validates against the closed schema" {
  export INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  local host_name host j
  for host_name in desktop laptop; do
    j="$(profile_loader_load "$host_name")" || { echo "profile_loader_load $host_name failed"; return 1; }
    run profile_loader_validate_schema host "$j"
    [ "$status" -eq 0 ] || { echo "host $host_name: $output"; return 1; }
  done
  for host in "$INSTALLER_DIR"/hosts/vm/*/; do
    host_name="${host%/}"; host_name="${host_name##*/}"
    j="$(profile_loader_load "$host_name")" || { echo "profile_loader_load vm/$host_name failed"; return 1; }
    run profile_loader_validate_schema host "$j"
    [ "$status" -eq 0 ] || { echo "host vm/$host_name: $output"; return 1; }
  done
}

@test "real: every user profile validates against the closed schema" {
  export INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  local user_directory user_name j
  for user_directory in "$INSTALLER_DIR"/users/*/; do
    user_name="${user_directory%/}"; user_name="${user_name##*/}"
    { [ "$user_name" = core ] || [ "$user_name" = vm ]; } && continue
    j="$(profile_loader_load_user "$user_name")" || { echo "load user $user_name failed"; return 1; }
    run profile_loader_validate_schema user "$j"
    [ "$status" -eq 0 ] || { echo "user $user_name: $output"; return 1; }
  done
  for user_directory in "$INSTALLER_DIR"/users/vm/*/; do
    user_name="${user_directory%/}"; user_name="${user_name##*/}"
    j="$(profile_loader_load_user "$user_name")" || { echo "load user vm/$user_name failed"; return 1; }
    run profile_loader_validate_schema user "$j"
    [ "$status" -eq 0 ] || { echo "user vm/$user_name: $output"; return 1; }
  done
}

@test "real: every program config.jsonc validates against the closed schema" {
  local installer_directory; installer_directory="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  local config_file j
  while IFS= read -r config_file; do
    j="$(jsonc_strip "$config_file" | jq '.')" || { echo "parse $config_file failed"; return 1; }
    run profile_loader_validate_schema program "$j"
    [ "$status" -eq 0 ] || { echo "program $config_file: $output"; return 1; }
  done < <(find "$installer_directory/programs" -name config.jsonc)
}


# ── migration tracer: arch-data is the first host on profile.jsonc ──────────
# Equivalence guard (ADR 0036): the migrated profile.jsonc must preserve every
# field the pre-migration (template-less) synthesis produced — captured below
# as software-only { sysctl, host_programs:[cups], users:[data] } — while
# adding the machine skeleton (disks excluded; picked at install). No
# host_profile; validates against the closed schema.

@test "migration: arch-data profile.jsonc preserves legacy software + machine skeleton" {
  export INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  local j; j="$(profile_loader_load arch-data)"

  # software preserved from the legacy synthesis (core + arch-data). cups left
  # core (ADR 0079) — it is toggle-derived and injected at assembly, not present
  # in the loaded (pre-assembly) profile — so host_programs is empty here.
  echo "$j" | jq -e '.users == ["data"]'
  echo "$j" | jq -e '(.host_programs // []) == []'
  echo "$j" | jq -e '.sysctl == {"vm.swappiness":10}'

  # machine skeleton present; devices excluded (operator-picked)
  echo "$j" | jq -e '.mode == "multi"'
  echo "$j" | jq -e '.os_pool.topology == "none"'
  echo "$j" | jq -e '([.data_pools[].name] | sort) == ["tank0","tank1"]'
  echo "$j" | jq -e '(.os_pool | has("disks")) | not'
  echo "$j" | jq -e '([.data_pools[] | has("disks")] | any) | not'

  # ADR 0036: no host_profile; whole thing validates closed-schema
  echo "$j" | jq -e 'has("host_profile") | not'
  run profile_loader_validate_schema host "$j"
  [ "$status" -eq 0 ]
}


# ── profile_loader_validate: validate host + referenced users + program configs ───
# The single validate-at-load entrypoint; the typo'd key in any of them
# aborts with its path (before any disk-touching phase).

@test "profile_loader_validate: passes for a clean host + users + programs" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" \
    '{"users":[],"host_programs":[]}'
  write_jsonc "$INSTALLER_DIR/hosts/desktop/profile.jsonc" \
    '{"users":["aquastias"],"host_programs":["grub"]}'
  write_jsonc "$INSTALLER_DIR/users/core/profile.jsonc" '{"programs":[]}'
  write_jsonc "$INSTALLER_DIR/users/aquastias/profile.jsonc" '{"programs":["neovim"]}'
  write_jsonc "$INSTALLER_DIR/programs/bootloader/grub/config.jsonc" \
    '{"name":"grub","kind":"host","description":"d"}'
  write_jsonc "$INSTALLER_DIR/programs/editors/neovim/config.jsonc" \
    '{"name":"neovim","kind":"user","description":"d"}'

  run profile_loader_validate desktop
  [ "$status" -eq 0 ]
}

@test "validate: object-form post_install validates clean (ADR 0041)" {
  run profile_loader_validate_schema host '{
    "post_install":{
      "security":{"firewall":"firewalld","antivirus":true,"rootkit":true,
                  "apparmor":true},
      "backup":{"zfs_auto_snapshot":true,"borg":true}
    }
  }'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "profile_loader_validate: rejects the old bool post_install form (ADR 0041)" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" \
    '{"users":[],"host_programs":[]}'
  write_jsonc "$INSTALLER_DIR/hosts/desktop/profile.jsonc" \
    '{"users":[],"host_programs":[],"post_install":{"security":false}}'

  run profile_loader_validate desktop
  [ "$status" -ne 0 ]
}

@test "profile_loader_validate: a typo'd key in a referenced program config aborts" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" \
    '{"users":[],"host_programs":[]}'
  write_jsonc "$INSTALLER_DIR/hosts/desktop/profile.jsonc" \
    '{"users":[],"host_programs":["grub"]}'
  write_jsonc "$INSTALLER_DIR/programs/bootloader/grub/config.jsonc" \
    '{"name":"grub","kidn":"host","description":"d"}'

  run profile_loader_validate desktop
  [ "$status" -ne 0 ]
  [[ "$output" == *"kidn"* ]]
}

@test "profile_loader_validate: a typo in a referenced user profile aborts with its path" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" \
    '{"users":[],"host_programs":[]}'
  write_jsonc "$INSTALLER_DIR/hosts/desktop/profile.jsonc" '{"users":["aquastias"]}'
  write_jsonc "$INSTALLER_DIR/users/core/profile.jsonc" '{}'
  write_jsonc "$INSTALLER_DIR/users/aquastias/profile.jsonc" '{"shel":"/bin/zsh"}'

  run profile_loader_validate desktop
  [ "$status" -ne 0 ]
  [[ "$output" == *"shel"* ]]
}

@test "profile_loader_validate: a typo in the host profile itself aborts with its path" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" '{"users":[]}'
  write_jsonc "$INSTALLER_DIR/hosts/desktop/profile.jsonc" \
    '{"options":{"encrytion":true}}'

  run profile_loader_validate desktop
  [ "$status" -ne 0 ]
  [[ "$output" == *"options.encrytion"* ]]
}

@test "profile_loader_validate: unknown bootloader aborts with its path (ADR 0077)" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" '{"users":[]}'
  write_jsonc "$INSTALLER_DIR/hosts/desktop/profile.jsonc" \
    '{"options":{"bootloader":"lilo"}}'

  run profile_loader_validate desktop
  [ "$status" -ne 0 ]
  [[ "$output" == *"options.bootloader"* ]]
  [[ "$output" == *"lilo"* ]]
}

@test "profile_loader_validate: a known bootloader validates clean (ADR 0077)" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" '{"users":[]}'
  write_jsonc "$INSTALLER_DIR/hosts/desktop/profile.jsonc" \
    '{"options":{"bootloader":"grub"}}'

  run profile_loader_validate desktop
  [ "$status" -eq 0 ]
}


# ── pool skeleton (no devices) ⇄ picker assignment (unified-host-profile/02) ─
# The profile carries the full pool skeleton minus devices; it must validate,
# and the effective config the picker assembles from it must validate too.

@test "validate: a pool skeleton with no device fields validates clean" {
  run profile_loader_validate_schema host '{
    "os_pool":{"pool_name":"rpool","topology":"mirror","ashift":13},
    "storage_groups":[{"name":"bulk","topology":"raidz1","mount":"/data",
                       "ashift":12,"owners":["a","@t"]}],
    "data_pools":[{"name":"scratch","topology":"stripe","mount":"/scratch",
                   "owners":["b"]}]
  }'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: per-group disk_count keys validate clean (ADR 0037)" {
  run profile_loader_validate_schema host '{
    "os_pool":{"pool_name":"rpool","topology":"none","disk_count":1},
    "storage_groups":[{"name":"data","topology":"raidz1","disk_count":3}],
    "data_pools":[{"name":"tank","topology":"mirror","disk_count":2}]
  }'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "integration: a picker-assigned effective config validates clean" {
  # picker_assign_disks comes from lib/picker.sh (sourced by profile.sh).
  local effective
  effective="$(picker_assign_disks \
    '{"os_pool":{"pool_name":"rpool","topology":"mirror"},
      "storage_groups":[{"name":"bulk","topology":"raidz1"}],
      "data_pools":[{"name":"scratch","topology":"stripe"}]}' \
    '{"mode":"multi","os_pool":["/dev/a","/dev/b"],
      "storage_groups":[["/dev/c","/dev/d","/dev/e"]],
      "data_pools":[["/dev/f","/dev/g"]]}')" \
    || { echo "assign failed"; return 1; }
  run profile_loader_validate_schema host "$effective"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "profile_loader_directory: a real host, else its hosts/vm/ fallback" {
  mkdir -p "$INSTALLER_DIR/hosts/desk" "$INSTALLER_DIR/hosts/vm/box"
  [ "$(profile_loader_directory hosts desk)" = "$INSTALLER_DIR/hosts/desk" ]
  [ "$(profile_loader_directory hosts box)" = "$INSTALLER_DIR/hosts/vm/box" ]
}
