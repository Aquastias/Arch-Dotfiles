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

# ── picker_enum_hosts ─────────────────────────────────────────────────────────

@test "picker_enum_hosts: only lists hosts shipping install.template.jsonc, sorted" {
  mkdir -p "$HOSTS_DIR/zeta" "$HOSTS_DIR/alpha" "$HOSTS_DIR/beta" \
           "$HOSTS_DIR/legacy" "$HOSTS_DIR/core"
  : > "$HOSTS_DIR/zeta/install.template.jsonc"
  : > "$HOSTS_DIR/alpha/install.template.jsonc"
  : > "$HOSTS_DIR/beta/install.template.jsonc"
  # legacy has only config.jsonc, no template
  : > "$HOSTS_DIR/legacy/config.jsonc"
  # core is reserved (merge base), never offered as a pickable host
  : > "$HOSTS_DIR/core/install.template.jsonc"

  run picker_enum_hosts "$HOSTS_DIR"
  [ "$status" -eq 0 ]
  expected="alpha
beta
zeta"
  [ "$output" = "$expected" ]
}

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
  run picker_validate_layout stripe 2
  [ "$status" -ne 0 ]
  [[ "$output" == *mode* ]] || [[ "$output" == *stripe* ]]
}

# ── picker_load_template ──────────────────────────────────────────────────────

@test "picker_load_template: host scalar overrides core scalar" {
  mkdir -p "$HOSTS_DIR/core" "$HOSTS_DIR/myhost"
  cat > "$HOSTS_DIR/core/install.template.jsonc" <<'JSONC'
{ "system": { "timezone": "UTC" } }
JSONC
  cat > "$HOSTS_DIR/myhost/install.template.jsonc" <<'JSONC'
{ "system": { "timezone": "Europe/Bucharest" } }
JSONC

  run picker_load_template "$HOSTS_DIR" myhost
  [ "$status" -eq 0 ]
  tz="$(echo "$output" | jq -r '.system.timezone')"
  [ "$tz" = "Europe/Bucharest" ]
}

@test "picker_load_template: nested objects deep-merge" {
  mkdir -p "$HOSTS_DIR/core" "$HOSTS_DIR/myhost"
  cat > "$HOSTS_DIR/core/install.template.jsonc" <<'JSONC'
{ "options": { "kernel": "lts", "encryption": false } }
JSONC
  cat > "$HOSTS_DIR/myhost/install.template.jsonc" <<'JSONC'
{ "options": { "encryption": true } }
JSONC

  run picker_load_template "$HOSTS_DIR" myhost
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.options.kernel')" = "lts" ]
  [ "$(echo "$output" | jq -r '.options.encryption')" = "true" ]
}

@test "picker_load_template: arrays concat and dedupe" {
  mkdir -p "$HOSTS_DIR/core" "$HOSTS_DIR/myhost"
  cat > "$HOSTS_DIR/core/install.template.jsonc" <<'JSONC'
{ "packages": { "extra": ["a", "b"] } }
JSONC
  cat > "$HOSTS_DIR/myhost/install.template.jsonc" <<'JSONC'
{ "packages": { "extra": ["b", "c"] } }
JSONC

  run picker_load_template "$HOSTS_DIR" myhost
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -c '.packages.extra')"
  [ "$result" = '["a","b","c"]' ]
}

@test "picker_load_template: missing host template → non-zero" {
  mkdir -p "$HOSTS_DIR/core"
  cat > "$HOSTS_DIR/core/install.template.jsonc" <<'JSONC'
{ "system": { "timezone": "UTC" } }
JSONC

  run picker_load_template "$HOSTS_DIR" nonexistent
  [ "$status" -ne 0 ]
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

# ── picker_assemble_config ────────────────────────────────────────────────────

@test "picker_assemble_config: writes hostname/mode/disk fresh" {
  template='{ "system": { "locale": "en_US.UTF-8", "timezone": "UTC" } }'
  run picker_assemble_config "$template" myhost single /dev/disk/by-id/foo
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.system.hostname')" = "myhost" ]
  [ "$(echo "$output" | jq -r '.mode')" = "single" ]
  [ "$(echo "$output" | jq -r '.disk')" = "/dev/disk/by-id/foo" ]
}

@test "picker_assemble_config: hostname overrides any template value" {
  template='{ "system": { "hostname": "OLD" } }'
  run picker_assemble_config "$template" newname single /dev/sda
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.system.hostname')" = "newname" ]
}

@test "picker_assemble_config: template fields pass through unchanged" {
  template='{ "options": { "kernel": "lts", "bootloader": "grub", "encryption": true } }'
  run picker_assemble_config "$template" h single /dev/sda
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.options.kernel')" = "lts" ]
  [ "$(echo "$output" | jq -r '.options.bootloader')" = "grub" ]
  [ "$(echo "$output" | jq -r '.options.encryption')" = "true" ]
}

@test "picker_enum_hosts: also lists vm/<name>/install.template.jsonc hosts" {
  mkdir -p "$HOSTS_DIR/desktop" "$HOSTS_DIR/vm/arch-kde" "$HOSTS_DIR/vm/no-tpl"
  : > "$HOSTS_DIR/desktop/install.template.jsonc"
  : > "$HOSTS_DIR/vm/arch-kde/install.template.jsonc"
  # vm/no-tpl has no template → omitted
  mkdir -p "$HOSTS_DIR/vm/no-tpl"

  run picker_enum_hosts "$HOSTS_DIR"
  [ "$status" -eq 0 ]
  expected="arch-kde
desktop"
  [ "$output" = "$expected" ]
}

@test "picker_load_template: falls back to <hosts_dir>/vm/<host>/ when top-level absent" {
  mkdir -p "$HOSTS_DIR/core" "$HOSTS_DIR/vm/arch-kde"
  cat > "$HOSTS_DIR/core/install.template.jsonc" <<'JSONC'
{ "system": { "timezone": "UTC" } }
JSONC
  cat > "$HOSTS_DIR/vm/arch-kde/install.template.jsonc" <<'JSONC'
{ "environment": { "desktop": "kde" } }
JSONC

  run picker_load_template "$HOSTS_DIR" arch-kde
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.system.timezone')" = "UTC" ]
  [ "$(echo "$output" | jq -r '.environment.desktop')" = "kde" ]
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

# ── picker_assemble_config: slice 3 (multi-disk) ─────────────────────────────

@test "picker_assemble_config: mirror + 2 disks → mode=multi, os_pool.topology=mirror" {
  template='{ "system": { "timezone": "UTC" } }'
  run picker_assemble_config "$template" myhost mirror \
    /dev/disk/by-id/d1 /dev/disk/by-id/d2
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.mode')" = "multi" ]
  [ "$(echo "$output" | jq -r '.os_pool.topology')" = "mirror" ]
  [ "$(echo "$output" | jq -c '.os_pool.disks')" = '["/dev/disk/by-id/d1","/dev/disk/by-id/d2"]' ]
  [ "$(echo "$output" | jq -r '.disk')" = "null" ]
}

@test "picker_assemble_config: raidz + 3 disks → mode=multi, os_pool.topology=raidz1" {
  template='{ "system": { "timezone": "UTC" } }'
  run picker_assemble_config "$template" myhost raidz \
    /dev/disk/by-id/d1 /dev/disk/by-id/d2 /dev/disk/by-id/d3
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.mode')" = "multi" ]
  [ "$(echo "$output" | jq -r '.os_pool.topology')" = "raidz1" ]
  [ "$(echo "$output" | jq -c '.os_pool.disks')" = '["/dev/disk/by-id/d1","/dev/disk/by-id/d2","/dev/disk/by-id/d3"]' ]
}

@test "picker_assemble_config: template os_pool fields pass through; disks override" {
  template='{ "os_pool": { "pool_name": "rpool", "ashift": 13, "disks": ["/old/disk"] } }'
  run picker_assemble_config "$template" h mirror /dev/d1 /dev/d2
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.os_pool.pool_name')" = "rpool" ]
  [ "$(echo "$output" | jq -r '.os_pool.ashift')" = "13" ]
  [ "$(echo "$output" | jq -r '.os_pool.topology')" = "mirror" ]
  [ "$(echo "$output" | jq -c '.os_pool.disks')" = '["/dev/d1","/dev/d2"]' ]
}

# ── picker_parse_choice (slice 4) ─────────────────────────────────────────────

@test "picker_parse_choice: 'i' → write_install" {
  run picker_parse_choice i
  [ "$status" -eq 0 ]
  [ "$output" = "write_install" ]
}

@test "picker_parse_choice: 'w' → write_only" {
  run picker_parse_choice w
  [ "$status" -eq 0 ]
  [ "$output" = "write_only" ]
}

@test "picker_parse_choice: 'e' → edit" {
  run picker_parse_choice e
  [ "$status" -eq 0 ]
  [ "$output" = "edit" ]
}

@test "picker_parse_choice: 'a' → abort" {
  run picker_parse_choice a
  [ "$status" -eq 0 ]
  [ "$output" = "abort" ]
}

@test "picker_parse_choice: unrecognised key → non-zero, no stdout" {
  run picker_parse_choice x
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "picker_parse_choice: empty input → non-zero, no stdout" {
  run picker_parse_choice ""
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

# ── picker_render_review (slice 4) ────────────────────────────────────────────

@test "picker_render_review: empty existing path → prints jsonc verbatim" {
  jsonc='{ "mode": "single", "disk": "/dev/disk/by-id/foo" }'
  run picker_render_review "$jsonc" ""
  [ "$status" -eq 0 ]
  [ "$output" = "$jsonc" ]
}

@test "picker_render_review: existing path absent → prints jsonc verbatim" {
  jsonc='{ "x": 1 }'
  run picker_render_review "$jsonc" "$TEST_DIR/does-not-exist.jsonc"
  [ "$status" -eq 0 ]
  [ "$output" = "$jsonc" ]
}

@test "picker_render_review: differing existing file → emits diff -u markers" {
  echo '{ "x": 1 }' > "$TEST_DIR/old.jsonc"
  run picker_render_review '{ "x": 2 }' "$TEST_DIR/old.jsonc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--- "* ]]
  [[ "$output" == *"+++ "* ]]
  [[ "$output" == *"-"*"\"x\": 1"* ]]
  [[ "$output" == *"+"*"\"x\": 2"* ]]
}

@test "picker_render_review: identical content → exits 0" {
  jsonc='{ "x": 1 }'
  echo "$jsonc" > "$TEST_DIR/old.jsonc"
  run picker_render_review "$jsonc" "$TEST_DIR/old.jsonc"
  [ "$status" -eq 0 ]
}
