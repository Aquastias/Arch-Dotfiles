#!/usr/bin/env bats
# Tests for .os/lib/config/profile.sh — Profile Loader + closed-schema
# validation + transient migration assembler (ADR 0036, issue
# unified-host-profile/01).
#
# Behaviour under test (external only — the effective config a loader
# produces, the errors a validator emits), never internal structure:
#   1. load_profile merges a real host profile.jsonc with core.
#   2. The loader reads ONLY profile.jsonc — a sibling legacy config.jsonc
#      is ignored, and a missing host profile.jsonc yields core-only (rc 1),
#      never a synthesized config (the transient scaffold is gone, issue 10).
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

@test "load_profile: finds a VM host profile.jsonc under hosts/vm/<name>" {
  write_jsonc "$OS_DIR/hosts/core/profile.jsonc" '{"system_programs":["cups"]}'
  write_jsonc "$OS_DIR/hosts/vm/arch-data/profile.jsonc" \
    '{"users":["vm-data"],"mode":"multi"}'

  run load_profile arch-data
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.users == ["vm-data"]'
  echo "$output" | jq -e '.system_programs == ["cups"]'
  echo "$output" | jq -e '.mode == "multi"'
}

# ── no dual-read: the loader reads ONLY profile.jsonc (issue 10) ───────────
# The transient scaffold is gone: a sibling legacy config.jsonc is ignored,
# and a host with no profile.jsonc yields core-only (rc 1), never a config
# synthesized from the legacy files.

@test "load_profile: ignores a sibling legacy config.jsonc (reads only profile)" {
  write_jsonc "$OS_DIR/hosts/core/profile.jsonc" '{"system_programs":["cups"]}'
  write_jsonc "$OS_DIR/hosts/desktop/profile.jsonc" '{"users":["bob"]}'
  # a leftover legacy config.jsonc with conflicting content must not be read
  write_jsonc "$OS_DIR/hosts/desktop/config.jsonc" \
    '{"users":["LEGACY"],"system_programs":["LEGACY"]}'

  run load_profile desktop
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.users == ["bob"]'
  echo "$output" | jq -e '.system_programs == ["cups"]'
}

@test "load_profile: missing host profile.jsonc → core only, rc 1 (no synth)" {
  write_jsonc "$OS_DIR/hosts/core/profile.jsonc" '{"system_programs":["cups"]}'
  # a legacy config.jsonc exists but must NOT be synthesized in
  write_jsonc "$OS_DIR/hosts/desktop/config.jsonc" '{"users":["LEGACY"]}'

  run load_profile desktop
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.system_programs == ["cups"]'
  echo "$output" | jq -e '(.users // []) == []'
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

@test "load_user_profile: missing user profile.jsonc → core only, rc 1 (no synth)" {
  write_jsonc "$OS_DIR/users/core/profile.jsonc" '{"shell":"/bin/bash"}'
  # a legacy user config.jsonc exists but must NOT be synthesized in
  write_jsonc "$OS_DIR/users/aquastias/config.jsonc" '{"sudo":true}'

  run load_user_profile aquastias
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.shell == "/bin/bash"'
  echo "$output" | jq -e '(.sudo // false) == false'
}

# ── loader contract: exit codes, merge rules, JSONC (moved from configs.bats) ─

@test "load_profile: missing core profile.jsonc is a hard error (exit 2)" {
  write_jsonc "$OS_DIR/hosts/desktop/profile.jsonc" '{"users":["alice"]}'

  run load_profile desktop
  [ "$status" -eq 2 ]
  [[ "$output" =~ "missing host core profile" ]]
}

@test "load_profile: 'core' as host name is rejected (exit 3)" {
  write_jsonc "$OS_DIR/hosts/core/profile.jsonc" '{"users":["alice"]}'

  run load_profile core
  [ "$status" -eq 3 ]
  [[ "$output" =~ "reserved name" ]]
}

@test "load_user_profile: 'core' as user name is rejected (exit 3)" {
  write_jsonc "$OS_DIR/users/core/profile.jsonc" '{"shell":"/bin/bash"}'

  run load_user_profile core
  [ "$status" -eq 3 ]
  [[ "$output" =~ "reserved name" ]]
}

@test "load_profile: arrays concat+dedupe, objects deep-merge, scalars win" {
  write_jsonc "$OS_DIR/hosts/core/profile.jsonc" \
    '{"users":["alice","shared"],"system":{"timezone":"UTC"}}'
  write_jsonc "$OS_DIR/hosts/desktop/profile.jsonc" \
    '{"users":["shared","bob"],"system":{"hostname":"eterniox"}}'

  run load_profile desktop
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.users == ["alice","shared","bob"]'
  echo "$output" | jq -e '.system.timezone == "UTC"'
  echo "$output" | jq -e '.system.hostname == "eterniox"'
}

@test "load_profile: JSONC // comments are stripped before parsing" {
  write_jsonc "$OS_DIR/hosts/core/profile.jsonc" '{
  // comment on its own line
  "users": ["alice"], // trailing comment
  "system_programs": ["cups"]
}'
  write_jsonc "$OS_DIR/hosts/desktop/profile.jsonc" '{}'

  run load_profile desktop
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.users == ["alice"]'
  echo "$output" | jq -e '.system_programs == ["cups"]'
}

# ── assemble_profile_config: the --profile effective-config seam ────────────
# Composes load_profile + picker_assign_disks + the dirname-is-identity
# hostname fallback (ADR 0036) into the transient effective config the
# install back-end consumes. Pure: no disks, no TTY.

@test "assemble_profile_config: hostname falls back to the profile name" {
  write_jsonc "$OS_DIR/hosts/core/profile.jsonc" '{"users":[]}'
  write_jsonc "$OS_DIR/hosts/arch-kde/profile.jsonc" \
    '{"environment":{"desktop":["kde"]}}'

  run assemble_profile_config arch-kde '{"mode":"single","disk":"/dev/sda"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "arch-kde"'
  echo "$output" | jq -e '.mode == "single"'
  echo "$output" | jq -e '.disk == "/dev/sda"'
  echo "$output" | jq -e 'has("host_profile") | not'
}

@test "assemble_profile_config: a profile-set hostname wins over the name" {
  write_jsonc "$OS_DIR/hosts/core/profile.jsonc" '{"users":[]}'
  write_jsonc "$OS_DIR/hosts/desktop/profile.jsonc" \
    '{"system":{"hostname":"eterniox"}}'

  run assemble_profile_config desktop '{"mode":"single","disk":"/dev/sda"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "eterniox"'
}

@test "assemble_profile_config: under-populated raidz1 aborts (min-disk)" {
  write_jsonc "$OS_DIR/hosts/core/profile.jsonc" '{"users":[]}'
  write_jsonc "$OS_DIR/hosts/srv/profile.jsonc" \
    '{"os_pool":{"topology":"raidz1"}}'

  run assemble_profile_config srv \
    '{"mode":"multi","os_pool":["/dev/sda","/dev/sdb"]}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"raidz1"* ]]
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

@test "validate: the options.zswap.* keys are accepted (closed schema)" {
  run validate_config_schema host \
    '{"options":{"zswap":{"enabled":true,"compressor":"zstd","max_pool_percent":20}}}'
  [ "$status" -eq 0 ]
}

@test "validate: a typo under options.zswap aborts with its path" {
  run validate_config_schema host '{"options":{"zswap":{"enabld":true}}}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"options.zswap.enabld"* ]]
}

@test "validate: unknown key in storage_groups[] aborts with its path" {
  run validate_config_schema host \
    '{"storage_groups":[{"name":"g","bogus":1}]}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"storage_groups[].bogus"* ]]
}

@test "validate: host_profile is dropped — the dirname is the identity" {
  # ADR 0036: host_profile is no longer a config field; --profile / the
  # host directory name is the identity. A leftover host_profile now aborts.
  run validate_config_schema host '{"host_profile":"desktop"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"host_profile"* ]]
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

@test "validate: system.locale and system.keymap accept arrays (issue 04)" {
  run validate_config_schema host \
    '{"system":{"locale":["en_US.UTF-8","de_DE.UTF-8"],"keymap":["us","de"]}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: a legacy scalar system.locale/keymap still validates" {
  run validate_config_schema host \
    '{"system":{"locale":"en_US.UTF-8","keymap":"us"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: options.ssh.enabled is accepted (issue 05)" {
  run validate_config_schema host '{"options":{"ssh":{"enabled":true}}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: filesystem + options.encryption_method are accepted (ADR 0040)" {
  run validate_config_schema host \
    '{"filesystem":"zfs","options":{"encryption_method":"native"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: per-group filesystem/encryption are accepted (ADR 0043)" {
  run validate_config_schema host '{
    "data_pools":[{"name":"tank0","filesystem":"ext4","encryption":true}],
    "storage_groups":[{"name":"bulk","filesystem":"btrfs","encryption":false}]
  }'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

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

@test "validate: a user profile accepts user_services[] (issue 06)" {
  run validate_config_schema user \
    '{"programs":["neovim"],"user_services":["podman.socket","syncthing"]}'
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

# ── migration tracer: arch-data is the first host on profile.jsonc ──────────
# Equivalence guard (ADR 0036): the migrated profile.jsonc must preserve every
# field the pre-migration (template-less) synthesis produced — captured below
# as software-only { sysctl, system_programs:[cups], users:[vm-data] } — while
# adding the machine skeleton (disks excluded; picked at install). No
# host_profile; validates against the closed schema.

@test "migration: arch-data profile.jsonc preserves legacy software + machine skeleton" {
  export OS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  local j; j="$(load_profile arch-data)"

  # software preserved from the legacy synthesis (core + arch-data)
  echo "$j" | jq -e '.users == ["vm-data"]'
  echo "$j" | jq -e '.system_programs == ["cups"]'
  echo "$j" | jq -e '.sysctl == {"vm.swappiness":10}'

  # machine skeleton present; devices excluded (operator-picked)
  echo "$j" | jq -e '.mode == "multi"'
  echo "$j" | jq -e '.os_pool.topology == "none"'
  echo "$j" | jq -e '([.data_pools[].name] | sort) == ["tank0","tank1"]'
  echo "$j" | jq -e '(.os_pool | has("disks")) | not'
  echo "$j" | jq -e '([.data_pools[] | has("disks")] | any) | not'

  # ADR 0036: no host_profile; whole thing validates closed-schema
  echo "$j" | jq -e 'has("host_profile") | not'
  run validate_config_schema host "$j"
  [ "$status" -eq 0 ]
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

@test "validate: object-form post_install validates clean (ADR 0041)" {
  run validate_config_schema host '{
    "post_install":{
      "security":{"firewall":"firewalld","antivirus":true,"rootkit":true,
                  "apparmor":true},
      "backup":{"zfs_auto_snapshot":true,"borg":true}
    }
  }'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_profile: rejects the old bool post_install form (ADR 0041)" {
  write_jsonc "$OS_DIR/hosts/core/profile.jsonc" \
    '{"users":[],"system_programs":[]}'
  write_jsonc "$OS_DIR/hosts/desktop/profile.jsonc" \
    '{"users":[],"system_programs":[],"post_install":{"security":false}}'

  run validate_profile desktop
  [ "$status" -ne 0 ]
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

@test "validate: per-group disk_count keys validate clean (ADR 0037)" {
  run validate_config_schema host '{
    "os_pool":{"pool_name":"rpool","topology":"none","disk_count":1},
    "storage_groups":[{"name":"data","topology":"raidz1","disk_count":3}],
    "data_pools":[{"name":"tank","topology":"mirror","disk_count":2}]
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
