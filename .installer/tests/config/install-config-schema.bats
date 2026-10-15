#!/usr/bin/env bats
# Tests: schema-driven accessors (split from install-config.bats;
# shared setup in install-config-helpers.bash)

load install-config-helpers


# ── Schema-driven loop: default-on-absent + value-on-present ─────────────────

@test "schema rows: default emitted when path absent, value emitted when present" {
  local spec name path kind default
  local test_json expected_present
  for spec in "${_INSTALL_CONFIG_SCHEMA[@]}"; do
    IFS='|' read -r name path kind default <<< "$spec"
    case "$kind" in
    scalar)
      test_json="\"X_${name}\""
      expected_present="X_${name}"
      ;;
    number)
      test_json="77"
      expected_present="77"
      ;;
    bool)
      if [[ "$default" == "true" ]]; then
        test_json="false"; expected_present="false"
      else
        test_json="true";  expected_present="true"
      fi
      ;;
    array)
      # kernels validates its tokens (ADR 0024), so it needs a real flavour
      expected_present="X_${name}"
      [[ "$name" == kernels ]] && expected_present="zen"
      test_json="[\"${expected_present}\"]"
      ;;
    *) printf 'unknown type %s for %s\n' "$kind" "$name" >&2; return 1 ;;
    esac

    # absent → default
    write_config '{}'
    out="$("install_config_${name}")" \
      || { echo "absent run failed for ${name}"; return 1; }
    [ "$out" = "${default//,/$'\n'}" ] \
      || { echo "[${name}] absent: got '$out', want default '$default'"; return 1; }

    # present → value
    set_path_config "$path" "$test_json"
    out="$("install_config_${name}")" \
      || { echo "present run failed for ${name}"; return 1; }
    [ "$out" = "$expected_present" ] \
      || { echo "[${name}] present: got '$out', want '$expected_present'"; \
           return 1; }
  done
}


# ── Bool null-distinction ────────────────────────────────────────────────────
# Literal null → default; explicit false → false.

@test "bool: literal null falls back to default (swap_enabled)" {
  write_config '{"options":{"swap":null}}'
  run install_config_swap_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "bool: explicit false stays false (swap_enabled)" {
  write_config '{"options":{"swap":false}}'
  run install_config_swap_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "bool: explicit true stays true (impermanence_enabled, default false)" {
  write_config '{"options":{"impermanence":{"enabled":true}}}'
  run install_config_impermanence_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "zswap: defaults on / zstd / 20 when absent" {
  write_config '{}'
  run install_config_zswap_enabled;          [ "$output" = "true" ]
  run install_config_zswap_compressor;       [ "$output" = "zstd" ]
  run install_config_zswap_max_pool_percent; [ "$output" = "20" ]
}

@test "zswap: explicit overrides win (false / lz4 / 40)" {
  write_config '{"options":{"zswap":{"enabled":false,"compressor":"lz4","max_pool_percent":40}}}'
  run install_config_zswap_enabled;          [ "$output" = "false" ]
  run install_config_zswap_compressor;       [ "$output" = "lz4" ]
  run install_config_zswap_max_pool_percent; [ "$output" = "40" ]
}


# ── Array union/null (string|array form, null, absent) ──────────────────────

@test "array: desktop string yields one line" {
  write_config '{"environment":{"desktop":"kde"}}'
  run install_config_desktop
  [ "$status" -eq 0 ]
  [ "$output" = "kde" ]
}

@test "array: desktop array yields one line per element" {
  write_config '{"environment":{"desktop":["kde"]}}'
  run install_config_desktop
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "kde" ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "array: desktop null yields empty (no default)" {
  write_config '{"environment":{"desktop":null}}'
  run install_config_desktop
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}


# ── Special: install_config_gpu (array w/ string default 'auto') ────────────

@test "gpu: string yields one line" {
  write_config '{"environment":{"gpu":"amd"}}'
  run install_config_gpu
  [ "$status" -eq 0 ]
  [ "$output" = "amd" ]
}

@test "gpu: array yields one line per element" {
  write_config '{"environment":{"gpu":["amd","nvidia"]}}'
  run install_config_gpu
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "amd" ]
  [ "${lines[1]}" = "nvidia" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "gpu: null yields default 'auto'" {
  write_config '{"environment":{"gpu":null}}'
  run install_config_gpu
  [ "$status" -eq 0 ]
  [ "$output" = "auto" ]
}

@test "gpu: absent yields default 'auto'" {
  write_config '{"environment":{}}'
  run install_config_gpu
  [ "$status" -eq 0 ]
  [ "$output" = "auto" ]
}


# ── Special: install_config_storage_group_ashift (positional arg) ───────────

@test "storage_group_ashift: returns field for given index" {
  write_config '{"storage_groups":[{"ashift":9},{"ashift":13}]}'
  run install_config_storage_group_ashift 1
  [ "$status" -eq 0 ]
  [ "$output" = "13" ]
}

@test "storage_group_ashift: returns default '12' when absent" {
  write_config '{"storage_groups":[{}]}'
  run install_config_storage_group_ashift 0
  [ "$status" -eq 0 ]
  [ "$output" = "12" ]
}


# ── Standalone Data Pools — data_pools[] accessors (ADR 0027) ────────────────

@test "data_pools_count: counts declared entries" {
  write_config '{"data_pools":[{"name":"a"},{"name":"b"}]}'
  run install_config_data_pools_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "data_pools_count: zero when absent" {
  write_config '{}'
  run install_config_data_pools_count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "data_pool_name: returns the entry name" {
  write_config '{"data_pools":[{"name":"tank0"}]}'
  run install_config_data_pool_name 0
  [ "$status" -eq 0 ]
  [ "$output" = "tank0" ]
}

@test "data_pool_topology: defaults to 'stripe' when absent" {
  write_config '{"data_pools":[{"name":"tank0"}]}'
  run install_config_data_pool_topology 0
  [ "$status" -eq 0 ]
  [ "$output" = "stripe" ]
}

@test "data_pool_topology: explicit value passes through" {
  write_config '{"data_pools":[{"name":"tank0","topology":"mirror"}]}'
  run install_config_data_pool_topology 0
  [ "$status" -eq 0 ]
  [ "$output" = "mirror" ]
}

@test "data_pool_mount: defaults to /data/<name>" {
  write_config '{"data_pools":[{"name":"tank0"}]}'
  run install_config_data_pool_mount 0
  [ "$status" -eq 0 ]
  [ "$output" = "/data/tank0" ]
}

@test "data_pool_mount: explicit mount passes through" {
  write_config '{"data_pools":[{"name":"tank0","mount":"/srv/tank"}]}'
  run install_config_data_pool_mount 0
  [ "$status" -eq 0 ]
  [ "$output" = "/srv/tank" ]
}

@test "data_pool_ashift: defaults to '12' when absent" {
  write_config '{"data_pools":[{"name":"tank0"}]}'
  run install_config_data_pool_ashift 0
  [ "$status" -eq 0 ]
  [ "$output" = "12" ]
}

@test "data_pool_disks: one device path per line" {
  write_config '{"data_pools":[{"name":"t","disks":["/dev/sdb","/dev/sdc"]}]}'
  run install_config_data_pool_disks 0
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/dev/sdb" ]
  [ "${lines[1]}" = "/dev/sdc" ]
  [ "${#lines[@]}" -eq 2 ]
}


# ── owners accessors (pool-owners, ADR 0031) ─────────────────────────────────

@test "data_pool_owners: one owner token per line" {
  write_config '{"data_pools":[{"name":"t","owners":["alice","@family"]}]}'
  run install_config_data_pool_owners 0
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "alice" ]
  [ "${lines[1]}" = "@family" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "data_pool_owners: empty when owners absent" {
  write_config '{"data_pools":[{"name":"t"}]}'
  run install_config_data_pool_owners 0
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "storage_group_owners: one owner token per line" {
  write_config '{"storage_groups":[{"name":"g","owners":["bob","@team"]}]}'
  run install_config_storage_group_owners 0
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "bob" ]
  [ "${lines[1]}" = "@team" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "storage_group_owners: empty when owners absent" {
  write_config '{"storage_groups":[{"name":"g"}]}'
  run install_config_storage_group_owners 0
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}


# ── Special: Kernel Selection (string|array list + primary bridge) ──────────

@test "kernels: absent defaults to lts" {
  write_config '{}'
  run install_config_kernels
  [ "$status" -eq 0 ]
  [ "$output" = "lts" ]
}

@test "kernels: scalar token yields a single-element list" {
  write_config '{"options":{"kernel":"default"}}'
  run install_config_kernels
  [ "$status" -eq 0 ]
  [ "$output" = "default" ]
}

@test "kernels: array yields one token per line, order preserved" {
  write_config '{"options":{"kernel":["default","lts"]}}'
  run install_config_kernels
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "default" ]
  [ "${lines[1]}" = "lts" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "kernel: primary is the first token of an array selection" {
  write_config '{"options":{"kernel":["default","lts"]}}'
  run install_config_kernel
  [ "$status" -eq 0 ]
  [ "$output" = "default" ]
}

@test "kernel: scalar selection passes through as primary" {
  write_config '{"options":{"kernel":"zen"}}'
  run install_config_kernel
  [ "$status" -eq 0 ]
  [ "$output" = "zen" ]
}

@test "kernels: unknown flavour token aborts config load" {
  write_config '{"options":{"kernel":"frobnicate"}}'
  run install_config_kernels
  [ "$status" -ne 0 ]
}

@test "kernels: an unknown token inside a list aborts" {
  write_config '{"options":{"kernel":["lts","frobnicate"]}}'
  run install_config_kernels
  [ "$status" -ne 0 ]
}


# ── locale/keymap arrays (issue 04): list + primary, scalar|array union ─────
# Mirrors Kernel Selection: install_config_locales/keymaps emit one token per
# line (primary first); install_config_locale/keymap return the primary
# (element 0). A scalar normalizes to a single-element list.

@test "locales: absent defaults to en_US.UTF-8" {
  write_config '{}'
  run install_config_locales
  [ "$status" -eq 0 ]
  [ "$output" = "en_US.UTF-8" ]
}

@test "locales: scalar yields a single-element list" {
  write_config '{"system":{"locale":"de_DE.UTF-8"}}'
  run install_config_locales
  [ "$status" -eq 0 ]
  [ "$output" = "de_DE.UTF-8" ]
}

@test "locales: array yields one per line, order preserved" {
  write_config '{"system":{"locale":["en_US.UTF-8","de_DE.UTF-8"]}}'
  run install_config_locales
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "en_US.UTF-8" ]
  [ "${lines[1]}" = "de_DE.UTF-8" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "locale: primary is the first element of an array selection" {
  write_config '{"system":{"locale":["en_US.UTF-8","de_DE.UTF-8"]}}'
  run install_config_locale
  [ "$status" -eq 0 ]
  [ "$output" = "en_US.UTF-8" ]
}

@test "locale: scalar passes through as primary" {
  write_config '{"system":{"locale":"fr_FR.UTF-8"}}'
  run install_config_locale
  [ "$status" -eq 0 ]
  [ "$output" = "fr_FR.UTF-8" ]
}

@test "keymaps: absent defaults to us" {
  write_config '{}'
  run install_config_keymaps
  [ "$status" -eq 0 ]
  [ "$output" = "us" ]
}

@test "keymaps: array yields one per line, order preserved" {
  write_config '{"system":{"keymap":["de","us","fr"]}}'
  run install_config_keymaps
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "de" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "keymap: primary is the first element" {
  write_config '{"system":{"keymap":["de","us"]}}'
  run install_config_keymap
  [ "$status" -eq 0 ]
  [ "$output" = "de" ]
}


# ── options.mirror_countries (issue 06): array special, default-5 ──────────
# Mirrors the Kernel/locale specials: one country per line, order preserved.
# Feeds `reflector --country`; the default is the operator's near-DE set.

@test "mirror_countries: absent yields the default five, in order" {
  write_config '{}'
  run install_config_mirror_countries
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Germany" ]
  [ "${lines[1]}" = "Switzerland" ]
  [ "${lines[2]}" = "Sweden" ]
  [ "${lines[3]}" = "France" ]
  [ "${lines[4]}" = "Romania" ]
  [ "${#lines[@]}" -eq 5 ]
}

@test "mirror_countries: an explicit array overrides, order preserved" {
  write_config '{"options":{"mirror_countries":["Japan","Australia"]}}'
  run install_config_mirror_countries
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Japan" ]
  [ "${lines[1]}" = "Australia" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "mirror_countries: a scalar string passes through as one element" {
  write_config '{"options":{"mirror_countries":"Romania"}}'
  run install_config_mirror_countries
  [ "$status" -eq 0 ]
  [ "$output" = "Romania" ]
}


# ── options.ssh.enabled (issue 05): bool toggle, default false ──────────────

@test "ssh_enabled: defaults false when absent" {
  write_config '{}'
  run install_config_ssh_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "ssh_enabled: true when options.ssh.enabled=true" {
  write_config '{"options":{"ssh":{"enabled":true}}}'
  run install_config_ssh_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}


# ── filesystem discriminator (ADR 0040): default zfs ────────────────────────

@test "filesystem: defaults to zfs when absent" {
  write_config '{}'
  run install_config_filesystem
  [ "$status" -eq 0 ]
  [ "$output" = "zfs" ]
}

@test "filesystem: an explicit value passes through" {
  write_config '{"filesystem":"btrfs"}'
  run install_config_filesystem
  [ "$status" -eq 0 ]
  [ "$output" = "btrfs" ]
}
