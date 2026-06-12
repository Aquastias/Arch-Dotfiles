#!/usr/bin/env bats
# Tests for .os/lib/picker.sh — Pre-Install Picker deep modules.

setup() {
  TEST_DIR="$(mktemp -d)"
  HOSTS_DIR="$TEST_DIR/hosts"
  mkdir -p "$HOSTS_DIR"
  export TEST_DIR HOSTS_DIR

  # shellcheck source=../lib/picker.sh
  source "$BATS_TEST_DIRNAME/../lib/picker.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── picker_validate_layout ────────────────────────────────────────────────────

@test "picker_validate_layout: single + 1 disk → ok" {
  run picker_validate_layout single 1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "picker_validate_layout: single + 0 disks → error" {
  run picker_validate_layout single 0
  [ "$status" -ne 0 ]
  [[ "$output" == *single* ]]
}

@test "picker_validate_layout: single + 2 disks → error" {
  run picker_validate_layout single 2
  [ "$status" -ne 0 ]
  [[ "$output" == *single* ]]
}

@test "picker_validate_layout: unknown mode → error" {
  run picker_validate_layout bogus 2
  [ "$status" -ne 0 ]
  [[ "$output" == *mode* ]] || [[ "$output" == *bogus* ]]
}

# ── picker_enum_disks ─────────────────────────────────────────────────────────

# Helpers: fake a by-id tree where each symlink points at a /dev/<base> node.
mk_by_id() {
  local link="$1" base="$2"
  ln -sf "../../$base" "$BY_ID/$link"
}
mk_dev() {
  : > "$DEV_ROOT/$1"
}

setup_disk_fixture() {
  DEV_ROOT="$TEST_DIR/dev"
  BY_ID="$DEV_ROOT/disk/by-id"
  mkdir -p "$BY_ID"
  export DEV_ROOT BY_ID PICKER_BY_ID_DIR="$BY_ID"
  # Two real disks
  mk_dev sda; mk_dev sda1; mk_dev sda2
  mk_dev sdb; mk_dev sdb1
  # Live USB
  mk_dev sdz; mk_dev sdz1
  mk_by_id "ata-Samsung_SSD_980_PRO_S1"     sda
  mk_by_id "ata-Samsung_SSD_980_PRO_S1-part1" sda1
  mk_by_id "ata-Samsung_SSD_980_PRO_S1-part2" sda2
  mk_by_id "nvme-WD_Black_SN850_X2"         sdb
  mk_by_id "nvme-WD_Black_SN850_X2-part1"   sdb1
  mk_by_id "usb-Kingston_DT_Live"           sdz
  mk_by_id "usb-Kingston_DT_Live-part1"     sdz1
}

@test "picker_enum_disks: excludes live medium and its partitions, sorted" {
  setup_disk_fixture
  run picker_enum_disks /dev/sdz
  [ "$status" -eq 0 ]
  expected="$BY_ID/ata-Samsung_SSD_980_PRO_S1
$BY_ID/ata-Samsung_SSD_980_PRO_S1-part1
$BY_ID/ata-Samsung_SSD_980_PRO_S1-part2
$BY_ID/nvme-WD_Black_SN850_X2
$BY_ID/nvme-WD_Black_SN850_X2-part1"
  [ "$output" = "$expected" ]
}

@test "picker_enum_disks: empty live arg → all disks listed" {
  setup_disk_fixture
  run picker_enum_disks ""
  [ "$status" -eq 0 ]
  count="$(echo "$output" | wc -l)"
  [ "$count" -eq 7 ]
}

# The Live-Medium Detector emits a SET (newline-separated whole disks); every
# disk in it — and its partitions — must be excluded, not just the first.
@test "picker_enum_disks: excludes every disk in the live-medium set" {
  setup_disk_fixture
  run picker_enum_disks "$(printf '/dev/sdz\n/dev/sdb\n')"
  [ "$status" -eq 0 ]
  expected="$BY_ID/ata-Samsung_SSD_980_PRO_S1
$BY_ID/ata-Samsung_SSD_980_PRO_S1-part1
$BY_ID/ata-Samsung_SSD_980_PRO_S1-part2"
  [ "$output" = "$expected" ]
}

# ── picker_format_disk_preview ────────────────────────────────────────────────

setup_preview_stubs() {
  mkdir -p "$TEST_DIR/bin" "$TEST_DIR/dev/disk/by-id"
  BY_ID="$TEST_DIR/dev/disk/by-id"
  export BY_ID
  export PATH="$TEST_DIR/bin:$PATH"
  : > "$TEST_DIR/dev/nvme0n1"
  ln -sf "../../nvme0n1" "$BY_ID/nvme-Samsung_SSD_980_PRO_S1"
}

_stub_lsblk() {
  local dno="$1" no="${2:-}"
  printf '%s\n' "$dno" > "$TEST_DIR/lsblk_dno.out"
  printf '%s\n' "$no"  > "$TEST_DIR/lsblk_no.out"
  cat > "$TEST_DIR/bin/lsblk" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  -dno) cat "$TEST_DIR/lsblk_dno.out" ;;
  -no)  cat "$TEST_DIR/lsblk_no.out"  ;;
esac
STUB
  chmod +x "$TEST_DIR/bin/lsblk"
}

_stub_smartctl() {
  local ec="$1" out="${2:-}"
  printf '%s\n' "$out" > "$TEST_DIR/smartctl.out"
  cat > "$TEST_DIR/bin/smartctl" <<STUB
#!/usr/bin/env bash
cat "\$TEST_DIR/smartctl.out"
exit $ec
STUB
  chmod +x "$TEST_DIR/bin/smartctl"
}

@test "picker_format_disk_preview: emits Disk section with lsblk -dno line" {
  setup_preview_stubs
  _stub_lsblk "nvme0n1 931.5G Samsung_SSD_980_PRO S6B0 nvme"
  _stub_smartctl 1

  run picker_format_disk_preview "$BY_ID/nvme-Samsung_SSD_980_PRO_S1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"── Disk ──"* ]]
  [[ "$output" == *"nvme0n1 931.5G Samsung_SSD_980_PRO S6B0 nvme"* ]]
}

@test "picker_format_disk_preview: emits Partitions section with lsblk -no tree" {
  setup_preview_stubs
  _stub_lsblk \
    "nvme0n1 931.5G Samsung_SSD_980_PRO S6B0 nvme" \
    "nvme0n1 931.5G
├─nvme0n1p1 1G vfat ESP
└─nvme0n1p2 930.5G zfs_member zroot"
  _stub_smartctl 1

  run picker_format_disk_preview "$BY_ID/nvme-Samsung_SSD_980_PRO_S1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"── Partitions ──"* ]]
  [[ "$output" == *"├─nvme0n1p1 1G vfat ESP"* ]]
}

@test "picker_format_disk_preview: includes SMART section when smartctl -i succeeds" {
  setup_preview_stubs
  _stub_lsblk "nvme0n1 931.5G Samsung_SSD_980_PRO S6B0 nvme" "nvme0n1 931.5G"
  _stub_smartctl 0 "=== START OF INFORMATION SECTION ===
Model Family:     Samsung based SSDs
Device Model:     Samsung SSD 980 PRO 1TB"

  run picker_format_disk_preview "$BY_ID/nvme-Samsung_SSD_980_PRO_S1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"── SMART ──"* ]]
  [[ "$output" == *"Model Family:     Samsung based SSDs"* ]]
}

@test "picker_format_disk_preview: omits SMART section when smartctl -i fails, still exits 0" {
  setup_preview_stubs
  _stub_lsblk "nvme0n1 931.5G Samsung_SSD_980_PRO S6B0 nvme" "nvme0n1 931.5G"
  _stub_smartctl 1 "smartctl error noise that must not appear"

  run picker_format_disk_preview "$BY_ID/nvme-Samsung_SSD_980_PRO_S1"
  [ "$status" -eq 0 ]
  [[ "$output" != *"── SMART ──"* ]]
  [[ "$output" != *"smartctl error noise"* ]]
}

@test "picker_format_disk_preview: full snapshot — Disk, SMART, Partitions in order" {
  setup_preview_stubs
  _stub_lsblk \
    "nvme0n1 931.5G Samsung_SSD_980_PRO S6B0 nvme" \
    "nvme0n1 931.5G
├─nvme0n1p1 1G vfat ESP
└─nvme0n1p2 930.5G zfs_member zroot"
  _stub_smartctl 0 "=== START OF INFORMATION SECTION ===
Model Family:     Samsung based SSDs
Device Model:     Samsung SSD 980 PRO 1TB"

  run picker_format_disk_preview "$BY_ID/nvme-Samsung_SSD_980_PRO_S1"
  [ "$status" -eq 0 ]
  expected="── Disk ──
nvme0n1 931.5G Samsung_SSD_980_PRO S6B0 nvme

── SMART ──
=== START OF INFORMATION SECTION ===
Model Family:     Samsung based SSDs
Device Model:     Samsung SSD 980 PRO 1TB

── Partitions ──
nvme0n1 931.5G
├─nvme0n1p1 1G vfat ESP
└─nvme0n1p2 930.5G zfs_member zroot"
  [ "$output" = "$expected" ]
}

@test "picker_format_disk_preview: missing by-id path → non-zero, clear error" {
  setup_preview_stubs
  _stub_lsblk "ignored" "ignored"
  _stub_smartctl 1

  run picker_format_disk_preview "$BY_ID/nvme-does-not-exist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"nvme-does-not-exist"* ]] || [[ "$output" == *"not found"* ]]
}

# ── picker_validate_layout: slice 3 (mirror, raidz) ──────────────────────────

@test "picker_validate_layout: mirror + 2 disks → ok" {
  run picker_validate_layout mirror 2
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "picker_validate_layout: mirror + 1 disk → error names mode and count" {
  run picker_validate_layout mirror 1
  [ "$status" -ne 0 ]
  [[ "$output" == *mirror* ]]
  [[ "$output" == *2* ]]
}

@test "picker_validate_layout: mirror + 3 disks → ok" {
  run picker_validate_layout mirror 3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "picker_validate_layout: raidz + 3 disks → ok" {
  run picker_validate_layout raidz 3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "picker_validate_layout: raidz + 2 disks → error names mode and count" {
  run picker_validate_layout raidz 2
  [ "$status" -ne 0 ]
  [[ "$output" == *raidz* ]]
  [[ "$output" == *3* ]]
}

@test "picker_validate_layout: raidz + 4 disks → ok" {
  run picker_validate_layout raidz 4
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── picker_validate_layout: pinned topologies (ADR 0029) ─────────────────────

@test "picker_validate_layout: stripe + 2 disks → ok" {
  run picker_validate_layout stripe 2
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "picker_validate_layout: stripe + 1 disk → error" {
  run picker_validate_layout stripe 1
  [ "$status" -ne 0 ]
  [[ "$output" == *stripe* ]]
}

@test "picker_validate_layout: raidz1 + 3 disks → ok; + 2 → error" {
  run picker_validate_layout raidz1 3
  [ "$status" -eq 0 ]
  run picker_validate_layout raidz1 2
  [ "$status" -ne 0 ]
  [[ "$output" == *raidz1* ]]
}

@test "picker_validate_layout: raidz2 + 4 disks → ok; + 3 → error" {
  run picker_validate_layout raidz2 4
  [ "$status" -eq 0 ]
  run picker_validate_layout raidz2 3
  [ "$status" -ne 0 ]
  [[ "$output" == *raidz2* ]]
  [[ "$output" == *4* ]]
}

@test "picker_validate_layout: none + 2 disks → ok; + 1 → error" {
  run picker_validate_layout none 2
  [ "$status" -eq 0 ]
  run picker_validate_layout none 1
  [ "$status" -ne 0 ]
  [[ "$output" == *none* ]]
}

