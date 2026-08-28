#!/usr/bin/env bats
# Tests for .os/vm/lib/profile-validate.sh — one test per validation rule.
# Prior art: tests/picker.bats (picker_validate_layout),
# tests/config/validation-*.bats.

setup() {
  TEST_DIR="$(mktemp -d)"
  HOSTS_DIR="$TEST_DIR/hosts"
  mkdir -p "$HOSTS_DIR"
  export TEST_DIR HOSTS_DIR

  # shellcheck source=../../vm/lib/profile-validate.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/profile-validate.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# A real host directory (unified profile.jsonc), for the host_profile
# reference rules — the validator only checks the host directory exists.
mk_host() {
  mkdir -p "$HOSTS_DIR/$1"
  : > "$HOSTS_DIR/$1/profile.jsonc"
}

# A minimal profile that passes every rule (inline install source).
valid_profile() {
  cat <<'JSONC'
{
  "name": "ok",
  "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
  "install": { "mode": "single", "disk": "/dev/sda" }
}
JSONC
}

@test "profile_validate: a fully valid profile is accepted, silently" {
  run profile_validate "$(valid_profile)" "$HOSTS_DIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "profile_validate: missing name → reject" {
  profile='{ "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
             "install": { "mode": "single" } }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *name* ]]
}

@test "profile_validate: empty disks array → reject" {
  profile='{ "name": "x",
             "hardware": { "disks": [], "ram_mb": 4096, "vcpus": 2 },
             "install": { "mode": "single" } }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *disks* ]]
}

@test "profile_validate: non-positive-int disk size → reject" {
  profile='{ "name": "x",
             "hardware": { "disks": [40, 0], "ram_mb": 4096, "vcpus": 2 },
             "install": { "mode": "single" } }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *disks* ]]
}

@test "profile_validate: two install sources (host_profile + install) → reject" {
  mk_host arch-kde
  profile='{ "name": "x",
             "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
             "host_profile": "arch-kde",
             "install": "repo" }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *source* ]]
}

@test "profile_validate: zero install sources → reject" {
  profile='{ "name": "x",
             "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 } }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *source* ]]
}

@test "profile_validate: nonexistent host_profile reference → reject" {
  # no host directory at all for 'ghost'
  profile='{ "name": "x",
             "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
             "host_profile": "ghost" }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *ghost* ]]
}

@test "profile_validate: host_profile with only profile.jsonc → accepted" {
  # A migrated, template-less host (arch-data shape) is a real host directory.
  mkdir -p "$HOSTS_DIR/arch-data"
  : > "$HOSTS_DIR/arch-data/profile.jsonc"
  profile='{ "name": "x",
             "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
             "host_profile": "arch-data" }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "profile_validate: host_profile referencing an existing host → accepted" {
  mk_host arch-kde
  profile='{ "name": "x",
             "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
             "host_profile": "arch-kde" }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "profile_validate: host_profile under hosts/vm/<name> → accepted" {
  mkdir -p "$HOSTS_DIR/vm/arch-data"
  : > "$HOSTS_DIR/vm/arch-data/profile.jsonc"
  profile='{ "name": "x",
             "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
             "host_profile": "arch-data" }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -eq 0 ]
}

@test "profile_validate: malformed verify.mounts (not dataset:/path) → reject" {
  profile='{ "name": "x",
             "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
             "install": { "mode": "single" },
             "verify": { "mounts": ["rpool/persist"] } }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *mounts* ]]
}

@test "profile_validate: well-formed verify.mounts → accepted" {
  profile='{ "name": "x",
             "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
             "install": { "mode": "single" },
             "verify": { "mounts": ["rpool/persist:/persist"] } }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -eq 0 ]
}

@test "profile_validate: malformed verify.owned (not /path:user) → reject" {
  profile='{ "name": "x",
             "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
             "install": { "mode": "single" },
             "verify": { "owned": ["data/tank:vm-data"] } }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *owned* ]]
}

@test "profile_validate: well-formed verify.owned → accepted" {
  profile='{ "name": "x",
             "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
             "install": { "mode": "single" },
             "verify": { "owned": ["/data/tank:vm-data"] } }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -eq 0 ]
}

@test "profile_validate: out-of-range ram_mb → reject" {
  profile='{ "name": "x",
             "hardware": { "disks": [40], "ram_mb": 64, "vcpus": 2 },
             "install": { "mode": "single" } }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *ram_mb* ]]
}

@test "profile_validate: out-of-range vcpus → reject" {
  profile='{ "name": "x",
             "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 0 },
             "install": { "mode": "single" } }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *vcpus* ]]
}

@test "profile_validate: missing ram_mb/vcpus → reject" {
  profile='{ "name": "x",
             "hardware": { "disks": [40] },
             "install": { "mode": "single" } }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -ne 0 ]
}

@test "profile_validate: out-of-range timeouts → reject" {
  profile='{ "name": "x",
             "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
             "install": { "mode": "single" },
             "timeouts": { "install": 999999 } }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *timeouts* ]]
}

@test "profile_validate: in-range timeouts → accepted" {
  profile='{ "name": "x",
             "hardware": { "disks": [40], "ram_mb": 4096, "vcpus": 2 },
             "install": { "mode": "single" },
             "timeouts": { "install": 3600, "boot": 600 } }'
  run profile_validate "$profile" "$HOSTS_DIR"
  [ "$status" -eq 0 ]
}
