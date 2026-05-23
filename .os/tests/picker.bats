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
  run picker_validate_layout mirror 2
  [ "$status" -ne 0 ]
  [[ "$output" == *mode* ]] || [[ "$output" == *mirror* ]]
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
