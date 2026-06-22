#!/usr/bin/env bats
# Tests for .os/lib/config/edits.sh — the Guided Installer's pure edit setters
# (ADR 0042). Each setter is JSON-in/JSON-out with no TTY, so behaviour is
# asserted through the public interface: a state + value in, the new state out,
# and the no-op rc/contract. These are the SET half shared by the replay helpers
# and the persistent-fzf controller.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/edits.sh"
}

# ── scalar / bool / array ───────────────────────────────────────────────────

@test "edit_set_scalar: sets a string at a dotted path" {
  run edit_set_scalar '{}' system.hostname "newhost"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.system.hostname' <<<"$output")" = "newhost" ]
}

@test "edit_set_scalar: empty input is a no-op (rc1, state unchanged)" {
  run edit_set_scalar '{"a":1}' system.hostname ""
  [ "$status" -eq 1 ]
  [ "$(jq -c . <<<"$output")" = '{"a":1}' ]
}

@test "edit_set_bool: sets true/false as a JSON bool" {
  run edit_set_bool '{}' options.encryption true
  [ "$status" -eq 0 ]
  [ "$(jq -c '.options.encryption' <<<"$output")" = "true" ]
}

@test "edit_set_bool: a non-bool is a no-op (rc1)" {
  run edit_set_bool '{}' options.encryption maybe
  [ "$status" -eq 1 ]
}

@test "edit_set_array: stores a JSON string array, order preserved" {
  run edit_set_array '{}' options.kernel lts zen
  [ "$status" -eq 0 ]
  [ "$(jq -c '.options.kernel' <<<"$output")" = '["lts","zen"]' ]
}

@test "edit_set_array: no values is a no-op (rc1)" {
  run edit_set_array '{}' options.kernel
  [ "$status" -eq 1 ]
}

# ── gpu ─────────────────────────────────────────────────────────────────────

@test "edit_set_gpu: vendors store an array" {
  run edit_set_gpu '{}' amd nvidia
  [ "$status" -eq 0 ]
  [ "$(jq -c '.environment.gpu' <<<"$output")" = '["amd","nvidia"]' ]
}

@test "edit_set_gpu: auto wins and clears vendors (scalar)" {
  run edit_set_gpu '{}' amd auto
  [ "$status" -eq 0 ]
  [ "$(jq -r '.environment.gpu' <<<"$output")" = "auto" ]
}

@test "edit_set_gpu: no pick is a no-op (rc1)" {
  run edit_set_gpu '{}'
  [ "$status" -eq 1 ]
}

# ── sysctl ──────────────────────────────────────────────────────────────────

@test "edit_set_sysctl: a dotted key is a LITERAL object key, numeric → number" {
  run edit_set_sysctl '{}' vm.swappiness 10
  [ "$status" -eq 0 ]
  [ "$(jq -c '.sysctl["vm.swappiness"]' <<<"$output")" = "10" ]
}

@test "edit_set_sysctl: a non-numeric value stays a string" {
  run edit_set_sysctl '{}' kernel.hostname box
  [ "$status" -eq 0 ]
  [ "$(jq -r '.sysctl["kernel.hostname"]' <<<"$output")" = "box" ]
}

@test "edit_set_sysctl: empty key is a no-op (rc1)" {
  run edit_set_sysctl '{}' "" 10
  [ "$status" -eq 1 ]
}

# ── list appends ────────────────────────────────────────────────────────────

@test "edit_append_packages: whitespace-split names append to packages.extra" {
  run edit_append_packages '{"packages":{"extra":["vim"]}}' "htop  btop"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.packages.extra' <<<"$output")" = '["vim","htop","btop"]' ]
}

@test "edit_append_packages: empty input is a no-op (rc1)" {
  run edit_append_packages '{}' ""
  [ "$status" -eq 1 ]
}

@test "edit_append_system_programs: dedup-appends" {
  run edit_append_system_programs '{"system_programs":["cups"]}' cups docker
  [ "$status" -eq 0 ]
  [ "$(jq -c '.system_programs' <<<"$output")" = '["cups","docker"]' ]
}

@test "edit_append_persist: appends an absolute dir" {
  run edit_append_persist '{}' /var/lib/foo
  [ "$status" -eq 0 ]
  [ "$(jq -c '.persist.directories' <<<"$output")" = '["/var/lib/foo"]' ]
}

# ── skeleton / users ────────────────────────────────────────────────────────

@test "edit_apply_skeleton: drops prior skeleton keys, merges the new one" {
  local prior='{"os_pool":{"topology":"stripe"},"data_pools":[{"name":"old"}]}'
  run edit_apply_skeleton "$prior" '{"os_pool":{"topology":"mirror"}}'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.os_pool.topology' <<<"$output")" = "mirror" ]
  [ "$(jq -c '.data_pools // "gone"' <<<"$output")" = '"gone"' ]
}

@test "edit_set_users: order-preserving dedup into users[]" {
  run edit_set_users '{}' aquastias bob aquastias
  [ "$status" -eq 0 ]
  [ "$(jq -c '.users' <<<"$output")" = '["aquastias","bob"]' ]
}

@test "edit_set_users: no names unsets the key (rc0 — clearing is a real edit)" {
  run edit_set_users '{"users":["x"]}'
  [ "$status" -eq 0 ]
  [ "$(jq -c '.users // "gone"' <<<"$output")" = '"gone"' ]
}
