#!/usr/bin/env bats
# Tests for the Guided Installer's two non-Proceed terminal actions (issue 08):
# Save profile (a device-less Host Profile delta over Host Core, re-installable
# via `install.sh --profile`) and Export effective config (the device-baked
# artifact, re-installable via `install.sh <config-file>`). The committed Save
# strips disks (0036's invariant: device paths are never repo source of truth);
# only Export carries them.

setup() {
  TEST_DIR="$(mktemp -d)"
  export OS_DIR="$TEST_DIR"

  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { :; }
  export -f info warn error section

  mkdir -p "$OS_DIR/hosts/core"
  printf '%s\n' \
    '{"system_programs":["cups"],"sysctl":{"vm.swappiness":10}}' \
    > "$OS_DIR/hosts/core/profile.jsonc"

  # shellcheck source=../../lib/config/state.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  # shellcheck source=../../lib/config/emit.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/emit.sh"
  # shellcheck source=../../lib/config/profile.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/profile.sh"
  # shellcheck source=../../lib/guided-save.sh
  source "$BATS_TEST_DIRNAME/../../lib/guided-save.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── tracer: the saved delta drops device paths, keeps the pool skeleton ──────

@test "guided_profile_delta: strips device paths, keeps the skeleton" {
  config='{"mode":"single","disk":"/dev/sda",
           "os_pool":{"topology":"mirror","disk_count":2,
                      "disks":["/dev/a","/dev/b"]}}'

  run guided_profile_delta "$config"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("disk") | not'              # single .disk dropped
  echo "$output" | jq -e '.os_pool | has("disks") | not'  # pool .disks[] dropped
  echo "$output" | jq -e '.os_pool.topology == "mirror"'  # skeleton kept
  echo "$output" | jq -e '.os_pool.disk_count == 2'
  echo "$output" | jq -e '.mode == "single"'
}

# ── Save writes a device-less, schema-valid profile that load_profile reads ──

@test "guided_save_host_profile: writes a device-less profile that re-loads" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  state="$(cfgstate_set "$state" mode '"single"')"
  state="$(cfgstate_set "$state" options.bootloader '"grub"')"

  run guided_save_host_profile "$state" "eterniox"
  [ "$status" -eq 0 ]
  [ -f "$OS_DIR/hosts/eterniox/profile.jsonc" ]
  # device-less + schema-clean + re-loadable via the Profile Loader
  run jq -e 'has("disk") | not' "$OS_DIR/hosts/eterniox/profile.jsonc"
  [ "$status" -eq 0 ]
  loaded="$(load_profile eterniox)"
  echo "$loaded" | jq -e '.options.bootloader == "grub"'   # delta applied
  echo "$loaded" | jq -e '.system_programs == ["cups"]'    # over Host Core
  run validate_config_schema host "$loaded"
  [ "$status" -eq 0 ]
}

# ── Save never overwrites — an existing profile forces a new name ────────────

@test "guided_save_host_profile: refuses to overwrite an existing profile" {
  mkdir -p "$OS_DIR/hosts/taken"
  printf 'KEEP\n' > "$OS_DIR/hosts/taken/profile.jsonc"
  state="$(cfgstate_set "$(cfgstate_new)" mode '"single"')"

  run guided_save_host_profile "$state" "taken"
  [ "$status" -ne 0 ]
  [ "$(cat "$OS_DIR/hosts/taken/profile.jsonc")" = "KEEP" ]   # untouched
}

# ── Export writes the device-baked config to a chosen path ──────────────────

@test "guided_export_config: writes the device-baked Effective Config" {
  effective='{"mode":"single","disk":"/dev/sda","system":{"hostname":"x"}}'
  out="$TEST_DIR/usb/eterniox.effective.jsonc"

  run guided_export_config "$effective" "$out"
  [ "$status" -eq 0 ]
  [ -f "$out" ]
  jq -e '.disk == "/dev/sda"' "$out"   # device paths ARE carried (re-installable)
}

# ── Export refuses to write into the repo's hosts/ tree ─────────────────────

@test "guided_export_config: refuses a path under hosts/" {
  run guided_export_config '{"mode":"single"}' "$OS_DIR/hosts/sneaky.jsonc"
  [ "$status" -ne 0 ]
  [ ! -f "$OS_DIR/hosts/sneaky.jsonc" ]
}
