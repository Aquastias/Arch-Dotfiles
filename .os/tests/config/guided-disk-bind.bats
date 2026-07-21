#!/usr/bin/env bats
# Tests for In-Menu Disk Binding — issue 02 (device-mode tracer for data pools).
# Two seams: pure resolvers (detect / free set / toggle / fs-pin trim / label)
# and the controller dispatch (the disk sub-screen render + toggle, and the
# pooledit disks row branching device-mode vs count-mode). A faked by-id tree
# via PICKER_BY_ID_DIR stands in for /dev/disk/by-id; GUIDED_LIVE_SET="" means
# no live-medium exclusion. No fzf, no real disks.

setup() {
  TEST_DIR="$(mktemp -d)"
  export GUIDED_STATE_FILE="$TEST_DIR/state.json"
  export GUIDED_NAV_FILE="$TEST_DIR/nav.json"
  export GUIDED_BASELINE_FILE="$TEST_DIR/base.json"

  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/nav.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/edits.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
  source "$BATS_TEST_DIRNAME/../../lib/guided-controller.sh"

  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  printf '%s\n' '{}' > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{"screen":"top"}' > "$GUIDED_NAV_FILE"

  BY_ID="$TEST_DIR/by-id"; mkdir -p "$BY_ID"
  export PICKER_BY_ID_DIR="$BY_ID" GUIDED_LIVE_SET=""
  : > "$TEST_DIR/n1"; : > "$TEST_DIR/n2"; : > "$TEST_DIR/a3"
  ln -sf ../n1 "$BY_ID/nvme-Disk_One"
  ln -sf ../n2 "$BY_ID/nvme-Disk_Two"
  ln -sf ../a3 "$BY_ID/ata-Disk_Three"
}
teardown() { rm -rf "$TEST_DIR"; }

set_nav() { printf '%s\n' "$1" > "$GUIDED_NAV_FILE"; }

# ── device-mode detection (AC1) ──────────────────────────────────────────────

@test "_ctl_detect_device_mode: disks present → device-mode" {
  [ "$(_ctl_detect_device_mode)" = "1" ]
}

@test "_ctl_detect_device_mode: no disks → count-mode" {
  rm -f "$BY_ID"/*
  [ "$(_ctl_detect_device_mode)" = "0" ]
}

# ── Free Set (AC3) ───────────────────────────────────────────────────────────

@test "_ctl_free_disks: all enumerated disks when nothing bound" {
  run _ctl_free_disks '{}'
  [ "$(echo "$output" | wc -l)" -eq 3 ]
}

@test "_ctl_free_disks: excludes a disk bound to a data pool" {
  local s
  s='{"data_pools":[{"name":"tank0","devices":["'"$BY_ID"'/nvme-Disk_One"]}]}'
  run _ctl_free_disks "$s"
  ! echo "$output" | grep -q "nvme-Disk_One"
  echo "$output" | grep -q "nvme-Disk_Two"
}

@test "_ctl_free_disks: excludes a disk bound to the os_pool (cross-group)" {
  local s='{"os_pool":{"devices":["'"$BY_ID"'/ata-Disk_Three"]}}'
  run _ctl_free_disks "$s"
  ! echo "$output" | grep -q "ata-Disk_Three"
  [ "$(echo "$output" | wc -l)" -eq 2 ]
}

# ── bind toggle + derived disk_count (AC2) ───────────────────────────────────

@test "_ctl_pool_toggle_disk: binds a disk, disk_count derives to 1" {
  local g; g="$(_ctl_pool_toggle_disk '{"name":"tank0"}' /dev/disk/by-id/x)"
  [ "$(jq -r '.devices[0]' <<<"$g")" = "/dev/disk/by-id/x" ]
  [ "$(jq -r '.disk_count' <<<"$g")" = "1" ]
}

@test "_ctl_pool_toggle_disk: toggling a bound disk unbinds it, count 0" {
  local g='{"name":"tank0","devices":["/dev/disk/by-id/x"],"disk_count":1}'
  g="$(_ctl_pool_toggle_disk "$g" /dev/disk/by-id/x)"
  [ "$(jq -c '.devices' <<<"$g")" = "[]" ]
  [ "$(jq -r '.disk_count' <<<"$g")" = "0" ]
}

# ── filesystem-pin trim (AC5) ────────────────────────────────────────────────

@test "_ctl_pool_normalise_fs: ext4 trims bound devices to the first" {
  local s='{"data_pools":[{"name":"t","devices":["/d/a","/d/b","/d/c"],
            "disk_count":3}]}'
  run _ctl_pool_normalise_fs "$s" 0 ext4
  [ "$(jq -c '.data_pools[0].devices' <<<"$output")" = '["/d/a"]' ]
  [ "$(jq -r '.data_pools[0].disk_count' <<<"$output")" = "1" ]
}

# ── disk label (AC4 — falls back to the by-id tail when lsblk can't read) ─────

@test "_ctl_disk_label: falls back to the by-id tail" {
  [ "$(_ctl_disk_label "$BY_ID/nvme-Disk_One")" = "nvme-Disk_One" ]
}

# When the by-id link resolves to a real /dev/ kernel node the label LEADS with
# it, so the operator recognises "/dev/sda …" — the by-id tail stays last (the
# parse-back key). A stubbed lsblk supplies size+model.
@test "_ctl_disk_label: leads with the /dev kernel name" {
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/lsblk" <<'STUB'
#!/usr/bin/env bash
echo "931.5G Samsung_SSD_980_PRO"
STUB
  chmod +x "$TEST_DIR/bin/lsblk"
  ln -sf /dev/null "$BY_ID/ata-Kernel_Named"
  export PATH="$TEST_DIR/bin:$PATH"
  run _ctl_disk_label "$BY_ID/ata-Kernel_Named"
  [ "$output" = "/dev/null 931.5G Samsung_SSD_980_PRO · ata-Kernel_Named" ]
}

# ── disk sub-screen render + toggle (AC4) ────────────────────────────────────

@test "list(pooldisks): bound disks marked, free disks unmarked, + Back" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","devices":["'"$BY_ID"'/nvme-Disk_One"]}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooldisks Disks 0 data)"
  run guided_ctl_list
  echo "$output" | grep -q '^\[x\] nvme-Disk_One'
  echo "$output" | grep -q '^\[ \] nvme-Disk_Two'
  echo "$output" | grep -q "← Back"
}

@test "enter(pooldisks): toggling a free disk binds it (refresh)" {
  printf '%s\n' '{"data_pools":[{"name":"tank0"}]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooldisks Disks 0 data)"
  run guided_ctl_enter "[ ] nvme-Disk_Two"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.data_pools[0].devices[0]' "$GUIDED_STATE_FILE")" \
    = "$BY_ID/nvme-Disk_Two" ]
  [ "$(jq -r '.data_pools[0].disk_count' "$GUIDED_STATE_FILE")" = "1" ]
}

@test "enter(pooldisks): a '<size> <model> · <tail>' label binds by its tail" {
  printf '%s\n' '{"data_pools":[{"name":"tank0"}]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooldisks Disks 0 data)"
  run guided_ctl_enter "[ ] 512G Foo SSD 980 · nvme-Disk_Two"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.data_pools[0].devices[0]' "$GUIDED_STATE_FILE")" \
    = "$BY_ID/nvme-Disk_Two" ]
}

@test "enter(pooldisks): ← Back returns to the pool editor (render)" {
  set_nav "$(nav_to_pooldisks Disks 0 data)"
  run guided_ctl_enter "← Back"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pooledit" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" index)" = "0" ]
}

# ── pooledit disks row: device-mode opens the sub-screen; count-mode cycles ──

@test "enter(pooledit): device-mode disks row opens the disk sub-screen" {
  GUIDED_DEVICE_MODE=1
  printf '%s\n' '{"data_pools":[{"name":"tank0","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0)"
  run guided_ctl_enter "disks: 0 bound   (Enter to edit)"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pooldisks" ]
}

@test "list(pooledit): device-mode 'N bound' vs count-mode cycle" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","devices":["'"$BY_ID"'/nvme-Disk_One"],
      "disk_count":1}]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0)"
  GUIDED_DEVICE_MODE=1 run guided_ctl_list
  echo "$output" | grep -q "disks: 1 bound"
  GUIDED_DEVICE_MODE=0 run guided_ctl_list
  echo "$output" | grep -q "disks: 1   (Enter cycles 1-8)"
}

@test "enter(pooledit): count-mode disks row still cycles the count" {
  GUIDED_DEVICE_MODE=0
  printf '%s\n' '{"data_pools":[{"name":"tank0","topology":"mirror",
    "disk_count":2}]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0)"
  run guided_ctl_enter "disks: 2   (Enter cycles 1-8)"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.data_pools[0].disk_count' "$GUIDED_STATE_FILE")" = "3" ]
}
