#!/usr/bin/env bats
# Tests for .os/vm/vm.sh — the profile-driven entry point (dry-run skeleton).
# OS_DIR is overridable so the CLI resolves profiles/hosts from a fixture tree
# while still sourcing the real vm/lib modules.

setup() {
  VM_SH="$BATS_TEST_DIRNAME/../../vm/vm.sh"
  OS_FIX="$(mktemp -d)"
  export OS_FIX

  # Hosts: core + a referenceable host with an Install Template.
  mkdir -p "$OS_FIX/hosts/core" "$OS_FIX/hosts/myhost"
  cat > "$OS_FIX/hosts/core/install.template.jsonc" <<'JSONC'
{ "system": { "locale": "en_US.UTF-8", "timezone": "UTC" }, "ashift": 12 }
JSONC
  cat > "$OS_FIX/hosts/myhost/install.template.jsonc" <<'JSONC'
{ "environment": { "desktop": "kde" }, "ashift": 13 }
JSONC

  # Committed repo config (the "repo" source).
  cat > "$OS_FIX/install.jsonc" <<'JSONC'
// committed
{ "system": { "hostname": "" }, "mode": "single", "disk": "/dev/sda" }
JSONC

  # Persistent profiles.
  mkdir -p "$OS_FIX/vm/profiles/cat" "$OS_FIX/vm/profiles/desktop"
  cat > "$OS_FIX/vm/profiles/cat/inline.jsonc" <<'JSONC'
{
  "name": "inline-case",
  "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
  "install": { "mode": "single", "disk": "/dev/sda", "ashift": 12 }
}
JSONC
  cat > "$OS_FIX/vm/profiles/cat/repo.jsonc" <<'JSONC'
{
  "name": "repo-case",
  "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
  "install": "repo"
}
JSONC
  cat > "$OS_FIX/vm/profiles/desktop/myhost.jsonc" <<'JSONC'
{
  "name": "myhost",
  "hardware": { "disks": [60], "ram_mb": 8192, "vcpus": 4 },
  "host_profile": "myhost",
  "layout": { "mode": "single" }
}
JSONC

  # Test profiles (same name, different tree — proves --testing flips the base).
  mkdir -p "$OS_FIX/tests/vm/profiles/cat"
  cat > "$OS_FIX/tests/vm/profiles/cat/inline.jsonc" <<'JSONC'
{
  "name": "TEST-inline",
  "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
  "install": { "mode": "single", "disk": "/dev/vda" }
}
JSONC
}

teardown() { rm -rf "$OS_FIX"; }

@test "vm.sh --print-config: inline profile resolves to its install block" {
  run env OS_DIR="$OS_FIX" "$VM_SH" --profile cat/inline --print-config
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.mode')" = "single" ]
  [ "$(echo "$output" | jq -r '.disk')" = "/dev/sda" ]
}

@test "vm.sh --print-config: host_profile profile merges the Install Template" {
  run env OS_DIR="$OS_FIX" "$VM_SH" --profile desktop/myhost --print-config
  [ "$status" -eq 0 ]
  # The resolved install config no longer carries host_profile (ADR 0036) — the
  # template merge is proven by the machine fields below.
  [ "$(echo "$output" | jq -r 'has("host_profile")')" = "false" ]
  [ "$(echo "$output" | jq -r '.mode')" = "single" ]
  [ "$(echo "$output" | jq -r '.disk')" = "/dev/sda" ]
  [ "$(echo "$output" | jq -r '.environment.desktop')" = "kde" ]
  [ "$(echo "$output" | jq -r '.ashift')" = "13" ]
}

@test "vm.sh --print-config: repo profile patches only the hostname" {
  run env OS_DIR="$OS_FIX" "$VM_SH" --profile cat/repo --print-config
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.system.hostname')" = "repo-case" ]
  [ "$(echo "$output" | jq -r '.disk')" = "/dev/sda" ]
}

@test "vm.sh --testing: flips profile resolution to the tests/vm tree" {
  run env OS_DIR="$OS_FIX" "$VM_SH" --testing --profile cat/inline --print-config
  [ "$status" -eq 0 ]
  # the test-tree profile installs to /dev/vda, the persistent one to /dev/sda
  [ "$(echo "$output" | jq -r '.disk')" = "/dev/vda" ]
}

@test "vm.sh: an invalid profile is rejected before any work" {
  mkdir -p "$OS_FIX/vm/profiles/bad"
  cat > "$OS_FIX/vm/profiles/bad/noname.jsonc" <<'JSONC'
{ "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
  "install": { "mode": "single" } }
JSONC
  run env OS_DIR="$OS_FIX" "$VM_SH" --profile bad/noname --print-config
  [ "$status" -ne 0 ]
  [[ "$output" == *name* ]]
}

@test "vm.sh: missing profile file → clear error" {
  run env OS_DIR="$OS_FIX" "$VM_SH" --profile cat/nope --print-config
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "vm.sh --help: prints usage and exits 0" {
  run env OS_DIR="$OS_FIX" "$VM_SH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--profile"* ]]
  [[ "$output" == *"--testing"* ]]
}

@test "vm.sh: no --profile → error" {
  run env OS_DIR="$OS_FIX" "$VM_SH" --print-config
  [ "$status" -ne 0 ]
  [[ "$output" == *profile* ]]
}
