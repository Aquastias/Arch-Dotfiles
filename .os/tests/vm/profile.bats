#!/usr/bin/env bats
# Tests for .os/vm/lib/profile.sh — VM Profile resolution (deep, pure).
# Prior art: tests/picker.bats (drives picker_assemble_config),
# tests/config/install-config.bats.

setup() {
  TEST_DIR="$(mktemp -d)"
  HOSTS_DIR="$TEST_DIR/hosts"
  mkdir -p "$HOSTS_DIR"
  export TEST_DIR HOSTS_DIR

  # shellcheck source=../../vm/lib/profile.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/profile.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── inline install source ────────────────────────────────────────────────────

@test "profile_resolve_config: inline install object is emitted verbatim" {
  profile='{
    "name": "t",
    "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
    "install": {
      "system": { "hostname": "inline-host" },
      "mode": "single",
      "disk": "/dev/sda"
    }
  }'
  run profile_resolve_config "$profile" "$HOSTS_DIR" /dev/null
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.system.hostname')" = "inline-host" ]
  [ "$(echo "$output" | jq -r '.mode')" = "single" ]
  [ "$(echo "$output" | jq -r '.disk')" = "/dev/sda" ]
}

# ── "repo" install source ────────────────────────────────────────────────────

@test "profile_resolve_config: repo emits committed config, only hostname patched" {
  cat > "$TEST_DIR/install.jsonc" <<'JSONC'
// committed default
{
  "system": { "hostname": "", "locale": "en_US.UTF-8", "timezone": "UTC" },
  "mode": "single",
  "disk": "/dev/sda",
  "ashift": 12
}
JSONC
  profile='{
    "name": "single-plain",
    "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
    "install": "repo"
  }'
  run profile_resolve_config "$profile" "$HOSTS_DIR" "$TEST_DIR/install.jsonc"
  [ "$status" -eq 0 ]
  # only hostname changes
  [ "$(echo "$output" | jq -r '.system.hostname')" = "single-plain" ]
  # everything else preserved verbatim
  [ "$(echo "$output" | jq -r '.system.locale')" = "en_US.UTF-8" ]
  [ "$(echo "$output" | jq -r '.mode')" = "single" ]
  [ "$(echo "$output" | jq -r '.disk')" = "/dev/sda" ]
  [ "$(echo "$output" | jq -r '.ashift')" = "12" ]
}

# ── host_profile install source ──────────────────────────────────────────────

# Build a core + host template pair under $HOSTS_DIR. $1=host name, rest piped
# from heredoc into the host template body.
mk_host_template() {
  mkdir -p "$HOSTS_DIR/core" "$HOSTS_DIR/$1"
  cat > "$HOSTS_DIR/core/install.template.jsonc" <<'JSONC'
{ "system": { "locale": "en_US.UTF-8", "timezone": "UTC" }, "ashift": 12 }
JSONC
  cat > "$HOSTS_DIR/$1/install.template.jsonc"
}

@test "profile_resolve_config: host_profile single matches picker_assemble_config" {
  mk_host_template myhost <<'JSONC'
{ "environment": { "desktop": "kde" }, "ashift": 13 }
JSONC
  profile='{
    "name": "myhost",
    "hardware": { "disks": [60], "ram_mb": 8192, "vcpus": 4 },
    "host_profile": "myhost",
    "layout": { "mode": "single" }
  }'
  run profile_resolve_config "$profile" "$HOSTS_DIR" /dev/null
  [ "$status" -eq 0 ]

  tpl="$(picker_load_template "$HOSTS_DIR" myhost)"
  expected="$(picker_assemble_config "$tpl" myhost single /dev/sda)"
  [ "$(echo "$output" | jq -S .)" = "$(echo "$expected" | jq -S .)" ]
}

@test "profile_resolve_config: unpinned multi derives /dev/sdX from disk count" {
  mk_host_template myhost <<'JSONC'
{ "environment": { "desktop": "kde" } }
JSONC
  profile='{
    "name": "myhost",
    "hardware": { "disks": [40, 40], "ram_mb": 8192, "vcpus": 4 },
    "host_profile": "myhost",
    "layout": { "mode": "mirror" }
  }'
  run profile_resolve_config "$profile" "$HOSTS_DIR" /dev/null
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.mode')" = "multi" ]
  [ "$(echo "$output" | jq -r '.os_pool.topology')" = "mirror" ]
  [ "$(echo "$output" | jq -c '.os_pool.disks')" = '["/dev/sda","/dev/sdb"]' ]
}

@test "profile_resolve_config: pinned multi template wins over layout.mode" {
  # template pins mode=multi + raidz1; layout.mode is bogus and must be ignored
  mk_host_template pinned <<'JSONC'
{ "mode": "multi", "os_pool": { "topology": "raidz1" } }
JSONC
  profile='{
    "name": "pinned",
    "hardware": { "disks": [20, 20, 20], "ram_mb": 4096, "vcpus": 2 },
    "host_profile": "pinned",
    "layout": { "mode": "single" }
  }'
  run profile_resolve_config "$profile" "$HOSTS_DIR" /dev/null
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.mode')" = "multi" ]
  [ "$(echo "$output" | jq -r '.os_pool.topology')" = "raidz1" ]
  [ "$(echo "$output" | jq -c '.os_pool.disks')" \
      = '["/dev/sda","/dev/sdb","/dev/sdc"]' ]
}

# ── new desktop templates are picker-enumerable ──────────────────────────────

@test "new arch-hyprland/arch-kde-hyprland templates appear in picker enum" {
  run picker_enum_hosts "$BATS_TEST_DIRNAME/../../hosts"
  [ "$status" -eq 0 ]
  [[ "$output" == *arch-hyprland* ]]
  [[ "$output" == *arch-kde-hyprland* ]]
}
