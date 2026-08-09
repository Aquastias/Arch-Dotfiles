#!/usr/bin/env bats
# Tests the declarative-path guardrails for Manual Partitioning (ADR 0073): a
# committed profile / pre-assembled config may not carry disk_config.kind=manual
# (it is Guided-Installer-only, never committed). _profile_reject_manual is the
# --profile Pre-Install Picker guard; the unattended install.sh <file> path
# reads the same kind via jsonc and rejects it. Pure: JSON in, no disks.

setup() {
  error() { echo "ERROR: $*" >&2; exit 1; }
  export -f error
  # jsonc for the unattended-path predicate (comment-tolerant read).
  source "$BATS_TEST_DIRNAME/../../lib/jsonc.sh"
  # Pull in _profile_reject_manual without booting the whole loader graph by
  # sourcing profile.sh with its heavy deps stubbed as already-present.
  layer_resolve() { :; }; _configs_merge() { :; }
  picker_assign_disks() { :; }; post_install_validate() { :; }
  export -f layer_resolve _configs_merge picker_assign_disks post_install_validate
  source "$BATS_TEST_DIRNAME/../../lib/config/profile.sh"
  TEST_DIR="$(mktemp -d)"
}
teardown() { rm -rf "$TEST_DIR"; }

# ── --profile / picker guard (_profile_reject_manual) ───────────────────────

@test "picker guard: a manual profile is rejected with an actionable message" {
  run _profile_reject_manual '{"disk_config":{"kind":"manual"}}' desktop
  [ "$status" -ne 0 ]
  [[ "$output" =~ manual ]]
  [[ "$output" =~ (Guided|guided) ]]
}

@test "picker guard: an auto profile passes" {
  run _profile_reject_manual '{"disk_config":{"kind":"auto"}}' desktop
  [ "$status" -eq 0 ]
}

@test "picker guard: a profile with no disk_config passes (defaults auto)" {
  run _profile_reject_manual '{"system":{"hostname":"x"}}' desktop
  [ "$status" -eq 0 ]
}

# ── unattended install.sh <file> guard (the jsonc kind read it uses) ────────

@test "unattended guard: reads kind=manual through JSONC comments" {
  cat > "$TEST_DIR/eff.jsonc" <<'EOF'
{
  // a hand-crafted effective config
  "disk_config": { "kind": "manual" }
}
EOF
  [ "$(jsonc_read "$TEST_DIR/eff.jsonc" '.disk_config.kind // "auto"')" \
    = "manual" ]
}

@test "unattended guard: an auto config reads as auto" {
  printf '%s\n' '{"filesystem":"ext4"}' > "$TEST_DIR/eff.jsonc"
  [ "$(jsonc_read "$TEST_DIR/eff.jsonc" '.disk_config.kind // "auto"')" \
    = "auto" ]
}
