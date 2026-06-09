#!/usr/bin/env bats
# Tests for .os/lib/config/profile.sh — Profile Loader + closed-schema
# validation + transient migration assembler (ADR 0036, issue
# unified-host-profile/01).
#
# Behaviour under test (external only — the effective config a loader
# produces, the errors a validator emits), never internal structure:
#   1. load_profile merges a real host profile.jsonc with core.
#   2. With no profile.jsonc, load_profile synthesizes the effective
#      config from the legacy install.template.jsonc + config.jsonc via
#      the existing picker assembler (transient scaffold).
#   3. The user path merges user profile.jsonc + user core.
#   4. Closed-schema validation rejects unknown keys at any depth (top
#      level, nested objects, arrays-of-objects), in host profile + core,
#      user profile + core, and program config.jsonc, reporting the
#      offending path before any disk-touching phase.

setup() {
  TEST_DIR="$(mktemp -d)"
  export OS_DIR="$TEST_DIR"

  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { :; }
  export -f info warn error section

  # shellcheck source=../../lib/config/profile.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/profile.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

write_jsonc() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
}

# ── load_profile: real profile.jsonc + core merge ──────────────────────────

@test "load_profile: merges real host profile.jsonc with core" {
  write_jsonc "$OS_DIR/hosts/core/profile.jsonc" \
    '{"users":["alice"],"system_programs":["cups"]}'
  write_jsonc "$OS_DIR/hosts/desktop/profile.jsonc" \
    '{"users":["bob"],"system":{"hostname":"eterniox"}}'

  run load_profile desktop
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.users == ["alice","bob"]'
  echo "$output" | jq -e '.system_programs == ["cups"]'
  echo "$output" | jq -e '.system.hostname == "eterniox"'
}

# ── transient scaffold: synthesize from legacy template + config ───────────
# When no profile.jsonc exists yet, the same effective config is rebuilt
# from the legacy install.template.jsonc (machine props) + config.jsonc
# (users/programs/packages), each already core+specific merged.

@test "load_profile: synthesizes from legacy template + config when no profile.jsonc" {
  write_jsonc "$OS_DIR/hosts/core/install.template.jsonc" \
    '{"system":{"locale":"en_US.UTF-8"},"options":{"bootloader":"systemd-boot"}}'
  write_jsonc "$OS_DIR/hosts/desktop/install.template.jsonc" \
    '{"system":{"hostname":"eterniox"}}'
  write_jsonc "$OS_DIR/hosts/core/config.jsonc" \
    '{"users":[],"system_programs":["cups"]}'
  write_jsonc "$OS_DIR/hosts/desktop/config.jsonc" \
    '{"users":["aquastias"],"system_programs":["grub"]}'

  run load_profile desktop
  [ "$status" -eq 0 ]
  # machine properties come from the template
  echo "$output" | jq -e '.system.hostname == "eterniox"'
  echo "$output" | jq -e '.system.locale == "en_US.UTF-8"'
  echo "$output" | jq -e '.options.bootloader == "systemd-boot"'
  # software comes from the config
  echo "$output" | jq -e '.users == ["aquastias"]'
  echo "$output" | jq -e '.system_programs == ["cups","grub"]'
}

@test "load_profile: synthesizes a template-less host from config alone" {
  write_jsonc "$OS_DIR/hosts/core/config.jsonc" \
    '{"users":[],"system_programs":["cups"]}'
  write_jsonc "$OS_DIR/hosts/arch-data/config.jsonc" \
    '{"users":["vm-data"]}'

  run load_profile arch-data
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.users == ["vm-data"]'
  echo "$output" | jq -e '.system_programs == ["cups"]'
}

# ── user path: profile.jsonc + user core (symmetric with the host path) ─────

@test "load_user_profile: merges real user profile.jsonc with core" {
  write_jsonc "$OS_DIR/users/core/profile.jsonc" \
    '{"shell":"/bin/bash","groups":["audio"]}'
  write_jsonc "$OS_DIR/users/aquastias/profile.jsonc" \
    '{"sudo":true,"groups":["video"]}'

  run load_user_profile aquastias
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.shell == "/bin/bash"'
  echo "$output" | jq -e '.sudo == true'
  echo "$output" | jq -e '.groups == ["audio","video"]'
}

@test "load_user_profile: synthesizes from legacy user config.jsonc when no profile.jsonc" {
  write_jsonc "$OS_DIR/users/core/config.jsonc" \
    '{"shell":"/bin/bash","programs":[]}'
  write_jsonc "$OS_DIR/users/aquastias/config.jsonc" \
    '{"sudo":true,"programs":["neovim"]}'

  run load_user_profile aquastias
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.shell == "/bin/bash"'
  echo "$output" | jq -e '.sudo == true'
  echo "$output" | jq -e '.programs == ["neovim"]'
}

# ── closed-schema validation: reject unknown keys at any depth ──────────────
# Any key the schema does not enumerate aborts with the offending path,
# before any disk-touching phase (ADR 0036, amends ADR 0015).

@test "validate: unknown top-level key in host profile aborts with its path" {
  run validate_config_schema host '{"optionz":{"bootloader":"grub"}}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"optionz"* ]]
}

@test "validate: unknown nested key aborts with the full path" {
  run validate_config_schema host \
    '{"options":{"impermanence":{"enabld":true}}}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"options.impermanence.enabld"* ]]
}

@test "validate: unknown key in storage_groups[] aborts with its path" {
  run validate_config_schema host \
    '{"storage_groups":[{"name":"g","bogus":1}]}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"storage_groups[].bogus"* ]]
}

@test "validate: unknown key in a user profile aborts" {
  run validate_config_schema user '{"shel":"/bin/zsh"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"shel"* ]]
}

@test "validate: unknown key in a program config aborts" {
  run validate_config_schema program \
    '{"name":"x","system":true,"desc":"y"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"desc"* ]]
}

@test "validate: a typo'd program 'system' key is caught (misroute guard)" {
  run validate_config_schema program \
    '{"name":"x","sytem":true,"description":"y"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"sytem"* ]]
}

# ── positive: representative valid configs pass clean ──────────────────────

@test "validate: a representative valid host profile passes" {
  run validate_config_schema host '{
    "system":{"hostname":"eterniox","locale":"en_US.UTF-8","keymap":"us"},
    "options":{"bootloader":"grub","impermanence":{"enabled":true}},
    "environment":{"desktop":["kde"],"gpu":"amd"},
    "storage_groups":[{"name":"g","topology":"mirror","owners":["a","@t"]}],
    "data_pools":[{"name":"tank","disks":["/dev/sdb"]}],
    "sysctl":{"vm.swappiness":10},
    "packages":{"repo":{"shell":["zsh"]},"groups":{"dev":["git"]}},
    "users":["aquastias"],"system_programs":["grub"]
  }'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: a representative valid user profile passes" {
  run validate_config_schema user '{
    "shell":"/bin/zsh","sudo":true,"groups":["audio","video"],
    "programs":["neovim"],"ssh_authorized_keys":[],
    "git":{"name":"A","email":"a@b.c"}
  }'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: a valid program config passes" {
  run validate_config_schema program \
    '{"name":"x","system":false,"description":"y"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── drift guard: reads (accessors.sh) and validation share the key set ─────
# Every _INSTALL_CONFIG_SCHEMA read-path must be a key the closed schema
# accepts; otherwise a field could be read but rejected (or vice versa).

@test "drift guard: every _INSTALL_CONFIG_SCHEMA read-path is a valid host key" {
  # shellcheck source=../../lib/config/accessors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"
  local spec n p t d j
  for spec in "${_INSTALL_CONFIG_SCHEMA[@]}"; do
    IFS='|' read -r n p t d <<< "$spec"
    j="$(jq -n "$p = \"x\"")" || { echo "bad jq path: $p"; return 1; }
    run validate_config_schema host "$j"
    [ "$status" -eq 0 ] \
      || { echo "read-path '$p' ($n) rejected by closed schema: $output"; \
           return 1; }
  done
}

# ── completeness: every real authored config validates clean ───────────────
# The forcing function — the schema must enumerate every key the live repo
# uses, or these break (and so would a real install).

@test "real: every host profile validates against the closed schema" {
  export OS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  local n h j
  for n in desktop laptop; do
    j="$(load_profile "$n")" || { echo "load_profile $n failed"; return 1; }
    run validate_config_schema host "$j"
    [ "$status" -eq 0 ] || { echo "host $n: $output"; return 1; }
  done
  for h in "$OS_DIR"/hosts/vm/*/; do
    n="$(basename "$h")"
    j="$(load_profile "$n")" || { echo "load_profile vm/$n failed"; return 1; }
    run validate_config_schema host "$j"
    [ "$status" -eq 0 ] || { echo "host vm/$n: $output"; return 1; }
  done
}

@test "real: every user profile validates against the closed schema" {
  export OS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  local u n j
  for u in "$OS_DIR"/users/*/; do
    n="$(basename "$u")"
    [ "$n" = core ] && continue
    j="$(load_user_profile "$n")" || { echo "load user $n failed"; return 1; }
    run validate_config_schema user "$j"
    [ "$status" -eq 0 ] || { echo "user $n: $output"; return 1; }
  done
}

@test "real: every program config.jsonc validates against the closed schema" {
  local os_dir; os_dir="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  local f j
  while IFS= read -r f; do
    j="$(jsonc_strip "$f" | jq '.')" || { echo "parse $f failed"; return 1; }
    run validate_config_schema program "$j"
    [ "$status" -eq 0 ] || { echo "program $f: $output"; return 1; }
  done < <(find "$os_dir/programs" -name config.jsonc)
}

# ── validate_profile: validate host + referenced users + program configs ───
# The single validate-at-load entrypoint; the typo'd key in any of them
# aborts with its path (before any disk-touching phase).

@test "validate_profile: passes for a clean host + users + programs" {
  write_jsonc "$OS_DIR/hosts/core/profile.jsonc" \
    '{"users":[],"system_programs":[]}'
  write_jsonc "$OS_DIR/hosts/desktop/profile.jsonc" \
    '{"users":["aquastias"],"system_programs":["grub"]}'
  write_jsonc "$OS_DIR/users/core/profile.jsonc" '{"programs":[]}'
  write_jsonc "$OS_DIR/users/aquastias/profile.jsonc" '{"programs":["neovim"]}'
  write_jsonc "$OS_DIR/programs/bootloader/grub/config.jsonc" \
    '{"name":"grub","system":true,"description":"d"}'
  write_jsonc "$OS_DIR/programs/editors/neovim/config.jsonc" \
    '{"name":"neovim","system":false,"description":"d"}'

  run validate_profile desktop
  [ "$status" -eq 0 ]
}

@test "validate_profile: a typo'd key in a referenced program config aborts" {
  write_jsonc "$OS_DIR/hosts/core/profile.jsonc" \
    '{"users":[],"system_programs":[]}'
  write_jsonc "$OS_DIR/hosts/desktop/profile.jsonc" \
    '{"users":[],"system_programs":["grub"]}'
  write_jsonc "$OS_DIR/programs/bootloader/grub/config.jsonc" \
    '{"name":"grub","sytem":true,"description":"d"}'

  run validate_profile desktop
  [ "$status" -ne 0 ]
  [[ "$output" == *"sytem"* ]]
}

@test "validate_profile: a typo in a referenced user profile aborts with its path" {
  write_jsonc "$OS_DIR/hosts/core/profile.jsonc" \
    '{"users":[],"system_programs":[]}'
  write_jsonc "$OS_DIR/hosts/desktop/profile.jsonc" '{"users":["aquastias"]}'
  write_jsonc "$OS_DIR/users/core/profile.jsonc" '{}'
  write_jsonc "$OS_DIR/users/aquastias/profile.jsonc" '{"shel":"/bin/zsh"}'

  run validate_profile desktop
  [ "$status" -ne 0 ]
  [[ "$output" == *"shel"* ]]
}

@test "validate_profile: a typo in the host profile itself aborts with its path" {
  write_jsonc "$OS_DIR/hosts/core/profile.jsonc" '{"users":[]}'
  write_jsonc "$OS_DIR/hosts/desktop/profile.jsonc" \
    '{"options":{"encrytion":true}}'

  run validate_profile desktop
  [ "$status" -ne 0 ]
  [[ "$output" == *"options.encrytion"* ]]
}

# ── pool skeleton (no devices) ⇄ picker assignment (unified-host-profile/02) ─
# The profile carries the full pool skeleton minus devices; it must validate,
# and the effective config the picker assembles from it must validate too.

@test "validate: a pool skeleton with no device fields validates clean" {
  run validate_config_schema host '{
    "os_pool":{"pool_name":"rpool","topology":"mirror","ashift":13},
    "storage_groups":[{"name":"bulk","topology":"raidz1","mount":"/data",
                       "ashift":12,"owners":["a","@t"]}],
    "data_pools":[{"name":"scratch","topology":"stripe","mount":"/scratch",
                   "owners":["b"]}]
  }'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "integration: a picker-assigned effective config validates clean" {
  # picker_assign_disks comes from lib/picker.sh (sourced by profile.sh).
  local eff
  eff="$(picker_assign_disks \
    '{"os_pool":{"pool_name":"rpool","topology":"mirror"},
      "storage_groups":[{"name":"bulk","topology":"raidz1"}],
      "data_pools":[{"name":"scratch","topology":"stripe"}]}' \
    '{"mode":"multi","os_pool":["/dev/a","/dev/b"],
      "storage_groups":[["/dev/c","/dev/d","/dev/e"]],
      "data_pools":[["/dev/f","/dev/g"]]}')" \
    || { echo "assign failed"; return 1; }
  run validate_config_schema host "$eff"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
