#!/usr/bin/env bats
# Tests for .os/vm/lib/profile.sh — VM Profile resolution (deep, pure).
# Prior art: tests/config/profile-loader.bats (load_profile +
# assemble_profile_config), tests/config/install-config.bats.

setup() {
  TEST_DIR="$(mktemp -d)"
  HOSTS_DIR="$TEST_DIR/hosts"
  mkdir -p "$HOSTS_DIR"
  # load_profile/assemble_profile_config resolve hosts under $OS_DIR/hosts.
  export TEST_DIR HOSTS_DIR OS_DIR="$TEST_DIR"

  # The config stack (layers.sh/jsonc.sh) emits through these — stub to quiet.
  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { :; }
  export -f info warn error section

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
  run profile_resolve_config "$profile"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.system.hostname')" = "inline-host" ]
  [ "$(echo "$output" | jq -r '.mode')" = "single" ]
  [ "$(echo "$output" | jq -r '.disk')" = "/dev/sda" ]
}

# ── "repo" install source ────────────────────────────────────────────────────

@test "profile_resolve_config: repo resolves as the default host_profile, single" {
  # install:"repo" ≡ host_profile: $VM_DEFAULT_HOST_PROFILE at single — the
  # shipped-default smoke survives the loss of the committed install.jsonc.
  mkdir -p "$HOSTS_DIR/core" "$HOSTS_DIR/$VM_DEFAULT_HOST_PROFILE"
  cat > "$HOSTS_DIR/core/profile.jsonc" <<'JSONC'
{ "system_programs": ["cups"] }
JSONC
  cat > "$HOSTS_DIR/$VM_DEFAULT_HOST_PROFILE/profile.jsonc" <<'JSONC'
{ "environment": { "desktop": ["kde"] } }
JSONC
  repo='{
    "name": "smoke",
    "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
    "install": "repo"
  }'
  via_host='{
    "name": "smoke",
    "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
    "host_profile": "'"$VM_DEFAULT_HOST_PROFILE"'",
    "layout": { "mode": "single" }
  }'
  run profile_resolve_config "$repo"
  [ "$status" -eq 0 ]
  # identical to resolving the default host directly, single-disk
  expected="$(profile_resolve_config "$via_host")"
  [ "$(echo "$output" | jq -S .)" = "$(echo "$expected" | jq -S .)" ]
  [ "$(echo "$output" | jq -c '.system_programs')" = '["cups"]' ]
  [ "$(echo "$output" | jq -r '.mode')" = "single" ]
  [ "$(echo "$output" | jq -r '.disk')" = "/dev/sda" ]
}

# ── host_profile resolves the unified profile.jsonc (load_profile) ───────────

@test "profile_resolve_config: host_profile single resolves via load_profile" {
  # A real profile.jsonc-backed host (no install.template.jsonc) — proves the
  # resolver reads the unified profile (merged over core) via load_profile,
  # not a copied Install Template.
  mkdir -p "$HOSTS_DIR/core" "$HOSTS_DIR/myhost"
  cat > "$HOSTS_DIR/core/profile.jsonc" <<'JSONC'
{ "system_programs": ["cups"] }
JSONC
  cat > "$HOSTS_DIR/myhost/profile.jsonc" <<'JSONC'
{ "environment": { "desktop": ["kde"] } }
JSONC
  profile='{
    "name": "vm-myhost",
    "hardware": { "disks": [60], "ram_mb": 8192, "vcpus": 4 },
    "host_profile": "myhost",
    "layout": { "mode": "single" }
  }'
  run profile_resolve_config "$profile"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.mode')" = "single" ]
  [ "$(echo "$output" | jq -r '.disk')" = "/dev/sda" ]
  # hostname falls back to the host-dir name (ADR 0036: dir ≡ hostname)
  [ "$(echo "$output" | jq -r '.system.hostname')" = "myhost" ]
  # software arrives via load_profile's core merge — impossible on the old
  # template-only path
  [ "$(echo "$output" | jq -c '.system_programs')" = '["cups"]' ]
  [ "$(echo "$output" | jq -c '.environment.desktop')" = '["kde"]' ]
}

@test "profile_resolve_config: host_profile pinned multi uses the profile topology" {
  # A multi host pins mode + os_pool.topology in its profile (ADR 0029); the VM
  # ships no layout.mode. All picked disks land in the OS pool at that topology.
  mkdir -p "$HOSTS_DIR/core" "$HOSTS_DIR/securehost"
  cat > "$HOSTS_DIR/core/profile.jsonc" <<'JSONC'
{ "os_pool": { "pool_name": "rpool" } }
JSONC
  cat > "$HOSTS_DIR/securehost/profile.jsonc" <<'JSONC'
{ "mode": "multi", "os_pool": { "topology": "mirror", "disk_count": 2 } }
JSONC
  profile='{
    "name": "vm-secure",
    "hardware": { "disks": [40, 40], "ram_mb": 6144, "vcpus": 4 },
    "host_profile": "securehost"
  }'
  run profile_resolve_config "$profile"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.mode')" = "multi" ]
  [ "$(echo "$output" | jq -r '.os_pool.topology')" = "mirror" ]
  [ "$(echo "$output" | jq -c '.os_pool.disks')" = '["/dev/sda","/dev/sdb"]' ]
  [ "$(echo "$output" | jq -r '.system.hostname')" = "securehost" ]
}

@test "profile_resolve_config: host_profile multi slices disks per disk_count" {
  # ADR 0037: a multi host declares disk_count per group; the VM's /dev/sdX
  # list is sliced onto os_pool → storage_groups[] → data_pools[] in declared
  # order, so a multi-data-pool host (arch-data-shaped) assembles.
  mkdir -p "$HOSTS_DIR/core" "$HOSTS_DIR/datahost"
  cat > "$HOSTS_DIR/core/profile.jsonc" <<'JSONC'
{ "os_pool": { "pool_name": "rpool" } }
JSONC
  cat > "$HOSTS_DIR/datahost/profile.jsonc" <<'JSONC'
{
  "mode": "multi",
  "os_pool": { "topology": "none", "disk_count": 1 },
  "data_pools": [
    { "name": "tank0", "topology": "stripe", "disk_count": 1 },
    { "name": "tank1", "topology": "mirror", "disk_count": 2 }
  ]
}
JSONC
  profile='{
    "name": "vm-data",
    "hardware": { "disks": [20, 20, 20, 20], "ram_mb": 4096, "vcpus": 2 },
    "host_profile": "datahost"
  }'
  run profile_resolve_config "$profile"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.mode')" = "multi" ]
  [ "$(echo "$output" | jq -c '.os_pool.disks')" = '["/dev/sda"]' ]
  [ "$(echo "$output" | jq -c '.data_pools[0].disks')" = '["/dev/sdb"]' ]
  [ "$(echo "$output" | jq -c '.data_pools[1].disks')" \
      = '["/dev/sdc","/dev/sdd"]' ]
}

@test "profile_resolve_config: VM disk count != sum(disk_count) aborts" {
  mkdir -p "$HOSTS_DIR/core" "$HOSTS_DIR/datahost"
  cat > "$HOSTS_DIR/core/profile.jsonc" <<'JSONC'
{ "os_pool": { "pool_name": "rpool" } }
JSONC
  cat > "$HOSTS_DIR/datahost/profile.jsonc" <<'JSONC'
{
  "mode": "multi",
  "os_pool": { "topology": "none", "disk_count": 1 },
  "data_pools": [ { "name": "tank1", "topology": "mirror", "disk_count": 2 } ]
}
JSONC
  profile='{
    "name": "vm-data",
    "hardware": { "disks": [20, 20], "ram_mb": 4096, "vcpus": 2 },
    "host_profile": "datahost"
  }'
  run profile_resolve_config "$profile"
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected 3"* ]]
}

@test "profile_resolve_config: unpinned host with a multi layout.mode is rejected" {
  # Decision X: multi topology comes only from the profile's os_pool pin. An
  # unpinned host can't conjure a topology from layout.mode — it must pin.
  mkdir -p "$HOSTS_DIR/core" "$HOSTS_DIR/plainhost"
  cat > "$HOSTS_DIR/core/profile.jsonc" <<'JSONC'
{ "os_pool": { "pool_name": "rpool" } }
JSONC
  cat > "$HOSTS_DIR/plainhost/profile.jsonc" <<'JSONC'
{ "environment": { "desktop": ["kde"] } }
JSONC
  profile='{
    "name": "vm-plain",
    "hardware": { "disks": [40, 40], "ram_mb": 4096, "vcpus": 2 },
    "host_profile": "plainhost",
    "layout": { "mode": "mirror" }
  }'
  run profile_resolve_config "$profile"
  [ "$status" -ne 0 ]
  [[ "$output" == *os_pool* ]]
}
