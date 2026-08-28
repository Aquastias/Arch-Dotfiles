#!/usr/bin/env bats
# Tests for the headless-replay In-Menu Disk Binding form — issue 07 (ADR 0047).
# In-menu binding is interactive-only; a `--guided` answers file injects each
# pool's bound by-id disks so the bound assignment path (issue 04) is scriptable
# for a VM. Asserts the Config State carries the injected devices[] (pure seam)
# and that a replayed bound layout bakes those exact disks WITHOUT a summed flat
# pick or an ACCEPT gate (assembly seam). No fzf, no real disks.

setup() {
  TEST_DIR="$(mktemp -d)"
  export INSTALLER_DIR="$TEST_DIR"

  info()    { echo "[info] $*"; }
  warn()    { echo "[warn] $*"; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { echo "== $* =="; }
  export -f info warn error section

  mkdir -p "$INSTALLER_DIR/hosts/core"
  printf '%s\n' '{"host_programs":["cups"]}' > "$INSTALLER_DIR/hosts/core/profile.jsonc"

  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/emit.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"

  live_medium_disks() { :; }
  # A flat pick would call this; the bound path must NOT, so make it fail loudly.
  picker_enum_disks() { echo "FLAT-PICK-SHOULD-NOT-RUN" >&2; return 1; }
  export -f live_medium_disks picker_enum_disks

  source "$BATS_TEST_DIRNAME/../../lib/guided.sh"
}
teardown() { rm -rf "$TEST_DIR"; }

write_answers() {
  local f="$TEST_DIR/answers"; printf '%s\n' "$@" > "$f"; printf '%s' "$f"
}

# ── device injection into the Config State (AC1) ─────────────────────────────

@test "_guided_edit_bound_devices: injects os_pool devices + derives count" {
  _GUIDED_REPLAY=1
  declare -gA _GUIDED_ANSWERS=(
    [os_pool_devices]="/dev/disk/by-id/wwn-A /dev/disk/by-id/wwn-B")
  _GUIDED_STATE='{"mode":"multi","os_pool":{"topology":"mirror","disk_count":2}}'
  _guided_edit_bound_devices
  [ "$(jq -c '.os_pool.devices' <<<"$_GUIDED_STATE")" \
    = '["/dev/disk/by-id/wwn-A","/dev/disk/by-id/wwn-B"]' ]
  [ "$(jq -r '.os_pool.disk_count' <<<"$_GUIDED_STATE")" = "2" ]
}

@test "_guided_edit_bound_devices: injects a data pool's devices by index" {
  _GUIDED_REPLAY=1
  declare -gA _GUIDED_ANSWERS=([data_0_devices]="/dev/disk/by-id/wwn-X")
  _GUIDED_STATE='{"mode":"multi","os_pool":{"topology":"none","disk_count":1},
                  "data_pools":[{"name":"tank0","topology":"stripe","disk_count":1}]}'
  _guided_edit_bound_devices
  [ "$(jq -c '.data_pools[0].devices' <<<"$_GUIDED_STATE")" \
    = '["/dev/disk/by-id/wwn-X"]' ]
  [ "$(jq -r '.data_pools[0].disk_count' <<<"$_GUIDED_STATE")" = "1" ]
}

@test "_guided_edit_bound_devices: no key leaves a group device-less" {
  _GUIDED_REPLAY=1
  declare -gA _GUIDED_ANSWERS=()
  _GUIDED_STATE='{"mode":"multi","os_pool":{"topology":"mirror","disk_count":2}}'
  _guided_edit_bound_devices
  [ "$(jq -r '.os_pool | has("devices")' <<<"$_GUIDED_STATE")" = "false" ]
}

# ── replayed bound layout bakes the disks via the slice-04 path (AC2) ─────────

@test "guided_build: a replayed bound os-mirror bakes the disks, no flat pick" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'layout=os-mirror' \
    'os_pool_devices=/dev/disk/by-id/wwn-A /dev/disk/by-id/wwn-B' \
    'confirm=INSTALL')"

  # No disks= and no accept_layout: the bound path must resolve without a flat
  # pick (picker_enum_disks fails loudly) and without the ACCEPT prompt.
  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.mode == "multi"'
  echo "$effective" | jq -e '.os_pool.topology == "mirror"'
  echo "$effective" | jq -e \
    '.os_pool.disks == ["/dev/disk/by-id/wwn-A","/dev/disk/by-id/wwn-B"]'
  # devices[] is transient — flattened out of the Effective Config.
  echo "$effective" | jq -e '(.os_pool | has("devices")) == false'
}

@test "guided_build: a bound data-pool layout bakes OS + data disks" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'layout=data-pools' \
    'os_pool_devices=/dev/disk/by-id/wwn-OS' \
    'data_0_devices=/dev/disk/by-id/wwn-D0' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.os_pool.disks == ["/dev/disk/by-id/wwn-OS"]'
  echo "$effective" | jq -e '.data_pools[0].disks == ["/dev/disk/by-id/wwn-D0"]'
}
