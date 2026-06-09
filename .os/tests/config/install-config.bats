#!/usr/bin/env bats
# Tests for .os/lib/config/accessors.sh — schema-driven Install Config reader.
#
# Structure (ADR 0015):
#   1. Parameterised loop over _INSTALL_CONFIG_SCHEMA — default-on-absent
#      and value-on-present per row.
#   2. Bool null-distinction — literal null falls back to default; explicit
#      false stays false.
#   3. Array union/null behaviour — string|array union, null, absent.
#   4. Four specials — gpu, packages_groups, storage_group_ashift, plus the
#      array-with-no-default behaviour.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"

  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { :; }
  export -f info warn error section

  # shellcheck source=../../lib/config/accessors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

write_cfg() { printf '%s\n' "$1" > "$CONFIG_FILE"; }

# Write a config that sets <jq_path> to <value> in an empty object.
# value must be a JSON literal (quoted strings, raw bools, raw arrays).
set_path_cfg() {
  local jq_path="$1" value="$2"
  echo '{}' | jq --argjson v "$value" "$jq_path = \$v" > "$CONFIG_FILE"
}

# ── Schema-driven loop: default-on-absent + value-on-present ─────────────────

@test "schema rows: default emitted when path absent, value emitted when present" {
  local spec n p t d
  local test_json expected_present
  for spec in "${_INSTALL_CONFIG_SCHEMA[@]}"; do
    IFS='|' read -r n p t d <<< "$spec"
    case "$t" in
    scalar)
      test_json="\"X_${n}\""
      expected_present="X_${n}"
      ;;
    bool)
      if [[ "$d" == "true" ]]; then
        test_json="false"; expected_present="false"
      else
        test_json="true";  expected_present="true"
      fi
      ;;
    array)
      test_json="[\"X_${n}\"]"
      expected_present="X_${n}"
      ;;
    *) printf 'unknown type %s for %s\n' "$t" "$n" >&2; return 1 ;;
    esac

    # absent → default
    write_cfg '{}'
    out="$("install_config_${n}")" \
      || { echo "absent run failed for ${n}"; return 1; }
    [ "$out" = "$d" ] \
      || { echo "[${n}] absent: got '$out', want default '$d'"; return 1; }

    # present → value
    set_path_cfg "$p" "$test_json"
    out="$("install_config_${n}")" \
      || { echo "present run failed for ${n}"; return 1; }
    [ "$out" = "$expected_present" ] \
      || { echo "[${n}] present: got '$out', want '$expected_present'"; \
           return 1; }
  done
}

# ── Bool null-distinction ────────────────────────────────────────────────────
# Literal null → default; explicit false → false.

@test "bool: literal null falls back to default (swap_enabled)" {
  write_cfg '{"options":{"swap":null}}'
  run install_config_swap_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "bool: explicit false stays false (swap_enabled)" {
  write_cfg '{"options":{"swap":false}}'
  run install_config_swap_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "bool: explicit true stays true (impermanence_enabled, default false)" {
  write_cfg '{"options":{"impermanence":{"enabled":true}}}'
  run install_config_impermanence_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# ── Array union/null (string|array form, null, absent) ──────────────────────

@test "array: desktop string yields one line" {
  write_cfg '{"environment":{"desktop":"kde"}}'
  run install_config_desktop
  [ "$status" -eq 0 ]
  [ "$output" = "kde" ]
}

@test "array: desktop array yields one line per element" {
  write_cfg '{"environment":{"desktop":["kde","hyprland"]}}'
  run install_config_desktop
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "kde" ]
  [ "${lines[1]}" = "hyprland" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "array: desktop null yields empty (no default)" {
  write_cfg '{"environment":{"desktop":null}}'
  run install_config_desktop
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "array: packages_extra empty array yields empty" {
  write_cfg '{"packages":{"extra":[]}}'
  run install_config_packages_extra
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── Special: install_config_gpu (array w/ string default 'auto') ────────────

@test "gpu: string yields one line" {
  write_cfg '{"environment":{"gpu":"amd"}}'
  run install_config_gpu
  [ "$status" -eq 0 ]
  [ "$output" = "amd" ]
}

@test "gpu: array yields one line per element" {
  write_cfg '{"environment":{"gpu":["amd","nvidia"]}}'
  run install_config_gpu
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "amd" ]
  [ "${lines[1]}" = "nvidia" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "gpu: null yields default 'auto'" {
  write_cfg '{"environment":{"gpu":null}}'
  run install_config_gpu
  [ "$status" -eq 0 ]
  [ "$output" = "auto" ]
}

@test "gpu: absent yields default 'auto'" {
  write_cfg '{"environment":{}}'
  run install_config_gpu
  [ "$status" -eq 0 ]
  [ "$output" = "auto" ]
}

# ── Special: install_config_packages_groups (custom jq filter) ──────────────

@test "packages_groups: flattens all groups into one list" {
  write_cfg '{"packages":{"groups":{"dev":["git","vim"],"media":["mpv"]}}}'
  run install_config_packages_groups
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "packages_groups: skips _-prefixed keys" {
  write_cfg '{"packages":{"groups":{"_comment":["ignored"],"dev":["git"]}}}'
  run install_config_packages_groups
  [ "$status" -eq 0 ]
  [ "$output" = "git" ]
}

@test "packages_groups: skips non-array values" {
  write_cfg '{"packages":{"groups":{"bogus":"oops","dev":["git"]}}}'
  run install_config_packages_groups
  [ "$status" -eq 0 ]
  [ "$output" = "git" ]
}

@test "packages_groups: absent yields empty" {
  write_cfg '{"packages":{}}'
  run install_config_packages_groups
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── Special: install_config_storage_group_ashift (positional arg) ───────────

@test "storage_group_ashift: returns field for given index" {
  write_cfg '{"storage_groups":[{"ashift":9},{"ashift":13}]}'
  run install_config_storage_group_ashift 1
  [ "$status" -eq 0 ]
  [ "$output" = "13" ]
}

@test "storage_group_ashift: returns default '12' when absent" {
  write_cfg '{"storage_groups":[{}]}'
  run install_config_storage_group_ashift 0
  [ "$status" -eq 0 ]
  [ "$output" = "12" ]
}

# ── Standalone Data Pools — data_pools[] accessors (ADR 0027) ────────────────

@test "data_pools_count: counts declared entries" {
  write_cfg '{"data_pools":[{"name":"a"},{"name":"b"}]}'
  run install_config_data_pools_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "data_pools_count: zero when absent" {
  write_cfg '{}'
  run install_config_data_pools_count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "data_pool_name: returns the entry name" {
  write_cfg '{"data_pools":[{"name":"tank0"}]}'
  run install_config_data_pool_name 0
  [ "$status" -eq 0 ]
  [ "$output" = "tank0" ]
}

@test "data_pool_topology: defaults to 'stripe' when absent" {
  write_cfg '{"data_pools":[{"name":"tank0"}]}'
  run install_config_data_pool_topology 0
  [ "$status" -eq 0 ]
  [ "$output" = "stripe" ]
}

@test "data_pool_topology: explicit value passes through" {
  write_cfg '{"data_pools":[{"name":"tank0","topology":"mirror"}]}'
  run install_config_data_pool_topology 0
  [ "$status" -eq 0 ]
  [ "$output" = "mirror" ]
}

@test "data_pool_mount: defaults to /data/<name>" {
  write_cfg '{"data_pools":[{"name":"tank0"}]}'
  run install_config_data_pool_mount 0
  [ "$status" -eq 0 ]
  [ "$output" = "/data/tank0" ]
}

@test "data_pool_mount: explicit mount passes through" {
  write_cfg '{"data_pools":[{"name":"tank0","mount":"/srv/tank"}]}'
  run install_config_data_pool_mount 0
  [ "$status" -eq 0 ]
  [ "$output" = "/srv/tank" ]
}

@test "data_pool_ashift: defaults to '12' when absent" {
  write_cfg '{"data_pools":[{"name":"tank0"}]}'
  run install_config_data_pool_ashift 0
  [ "$status" -eq 0 ]
  [ "$output" = "12" ]
}

@test "data_pool_disks: one device path per line" {
  write_cfg '{"data_pools":[{"name":"t","disks":["/dev/sdb","/dev/sdc"]}]}'
  run install_config_data_pool_disks 0
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/dev/sdb" ]
  [ "${lines[1]}" = "/dev/sdc" ]
  [ "${#lines[@]}" -eq 2 ]
}

# ── owners accessors (pool-owners, ADR 0031) ─────────────────────────────────

@test "data_pool_owners: one owner token per line" {
  write_cfg '{"data_pools":[{"name":"t","owners":["alice","@family"]}]}'
  run install_config_data_pool_owners 0
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "alice" ]
  [ "${lines[1]}" = "@family" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "data_pool_owners: empty when owners absent" {
  write_cfg '{"data_pools":[{"name":"t"}]}'
  run install_config_data_pool_owners 0
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "storage_group_owners: one owner token per line" {
  write_cfg '{"storage_groups":[{"name":"g","owners":["bob","@team"]}]}'
  run install_config_storage_group_owners 0
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "bob" ]
  [ "${lines[1]}" = "@team" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "storage_group_owners: empty when owners absent" {
  write_cfg '{"storage_groups":[{"name":"g"}]}'
  run install_config_storage_group_owners 0
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── Special: Kernel Selection (string|array list + primary bridge) ──────────

@test "kernels: absent defaults to lts" {
  write_cfg '{}'
  run install_config_kernels
  [ "$status" -eq 0 ]
  [ "$output" = "lts" ]
}

@test "kernels: scalar token yields a single-element list" {
  write_cfg '{"options":{"kernel":"default"}}'
  run install_config_kernels
  [ "$status" -eq 0 ]
  [ "$output" = "default" ]
}

@test "kernels: array yields one token per line, order preserved" {
  write_cfg '{"options":{"kernel":["default","lts"]}}'
  run install_config_kernels
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "default" ]
  [ "${lines[1]}" = "lts" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "kernel: primary is the first token of an array selection" {
  write_cfg '{"options":{"kernel":["default","lts"]}}'
  run install_config_kernel
  [ "$status" -eq 0 ]
  [ "$output" = "default" ]
}

@test "kernel: scalar selection passes through as primary" {
  write_cfg '{"options":{"kernel":"zen"}}'
  run install_config_kernel
  [ "$status" -eq 0 ]
  [ "$output" = "zen" ]
}

@test "kernels: unknown flavour token aborts config load" {
  write_cfg '{"options":{"kernel":"frobnicate"}}'
  run install_config_kernels
  [ "$status" -ne 0 ]
}

@test "kernels: an unknown token inside a list aborts" {
  write_cfg '{"options":{"kernel":["lts","frobnicate"]}}'
  run install_config_kernels
  [ "$status" -ne 0 ]
}

# ── locale/keymap arrays (issue 04): list + primary, scalar|array union ─────
# Mirrors Kernel Selection: install_config_locales/keymaps emit one token per
# line (primary first); install_config_locale/keymap return the primary
# (element 0). A scalar normalizes to a single-element list.

@test "locales: absent defaults to en_US.UTF-8" {
  write_cfg '{}'
  run install_config_locales
  [ "$status" -eq 0 ]
  [ "$output" = "en_US.UTF-8" ]
}

@test "locales: scalar yields a single-element list" {
  write_cfg '{"system":{"locale":"de_DE.UTF-8"}}'
  run install_config_locales
  [ "$status" -eq 0 ]
  [ "$output" = "de_DE.UTF-8" ]
}

@test "locales: array yields one per line, order preserved" {
  write_cfg '{"system":{"locale":["en_US.UTF-8","de_DE.UTF-8"]}}'
  run install_config_locales
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "en_US.UTF-8" ]
  [ "${lines[1]}" = "de_DE.UTF-8" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "locale: primary is the first element of an array selection" {
  write_cfg '{"system":{"locale":["en_US.UTF-8","de_DE.UTF-8"]}}'
  run install_config_locale
  [ "$status" -eq 0 ]
  [ "$output" = "en_US.UTF-8" ]
}

@test "locale: scalar passes through as primary" {
  write_cfg '{"system":{"locale":"fr_FR.UTF-8"}}'
  run install_config_locale
  [ "$status" -eq 0 ]
  [ "$output" = "fr_FR.UTF-8" ]
}

@test "keymaps: absent defaults to us" {
  write_cfg '{}'
  run install_config_keymaps
  [ "$status" -eq 0 ]
  [ "$output" = "us" ]
}

@test "keymaps: array yields one per line, order preserved" {
  write_cfg '{"system":{"keymap":["de","us","fr"]}}'
  run install_config_keymaps
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "de" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "keymap: primary is the first element" {
  write_cfg '{"system":{"keymap":["de","us"]}}'
  run install_config_keymap
  [ "$status" -eq 0 ]
  [ "$output" = "de" ]
}

# ── options.ssh.enabled (issue 05): bool toggle, default false ──────────────

@test "ssh_enabled: defaults false when absent" {
  write_cfg '{}'
  run install_config_ssh_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "ssh_enabled: true when options.ssh.enabled=true" {
  write_cfg '{"options":{"ssh":{"enabled":true}}}'
  run install_config_ssh_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# ── install_config_get: unknown name errors ─────────────────────────────────

@test "install_config_get: unknown name exits non-zero" {
  write_cfg '{}'
  run install_config_get bogus_field
  [ "$status" -ne 0 ]
}
