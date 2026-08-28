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

@test "edit_append_packages: split names append to packages.repo.extra" {
  local s='{"packages":{"repo":{"extra":["vim"]}}}'
  run edit_append_packages "$s" "htop  btop"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.packages.repo.extra' <<<"$output")" = '["vim","htop","btop"]' ]
}

@test "edit_append_packages: empty input is a no-op (rc1)" {
  run edit_append_packages '{}' ""
  [ "$status" -eq 1 ]
}

@test "edit_append_host_programs: dedup-appends" {
  run edit_append_host_programs '{"host_programs":["cups"]}' cups docker
  [ "$status" -eq 0 ]
  [ "$(jq -c '.host_programs' <<<"$output")" = '["cups","docker"]' ]
}

@test "edit_append_persist: appends an absolute dir" {
  run edit_append_persist '{}' /var/lib/foo
  [ "$status" -eq 0 ]
  [ "$(jq -c '.persist.directories' <<<"$output")" = '["/var/lib/foo"]' ]
}

@test "edit_remove_persist: removes a listed dir" {
  run edit_remove_persist '{"persist":{"directories":["/a","/b"]}}' /a
  [ "$status" -eq 0 ]
  [ "$(jq -c '.persist.directories' <<<"$output")" = '["/b"]' ]
}

@test "edit_remove_persist: an absent dir is a no-op (rc 1, unchanged)" {
  run edit_remove_persist '{"persist":{"directories":["/a"]}}' /x
  [ "$status" -eq 1 ]
  [ "$(jq -c '.persist.directories' <<<"$output")" = '["/a"]' ]
}

@test "edit_remove_persist: empty input is a no-op (rc 1)" {
  run edit_remove_persist '{"persist":{"directories":["/a"]}}' ""
  [ "$status" -eq 1 ]
  [ "$(jq -c '.persist.directories' <<<"$output")" = '["/a"]' ]
}

@test "edit_remove_persist: removing the last entry leaves an empty list" {
  run edit_remove_persist '{"persist":{"directories":["/a"]}}' /a
  [ "$status" -eq 0 ]
  [ "$(jq -c '.persist.directories' <<<"$output")" = '[]' ]
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

# ── routing-heavy adds shared with the controller (Candidate 3 / ADR 0072) ──

@test "edit_add_sysctl_pair: parses key=value into a sysctl pair" {
  run edit_add_sysctl_pair '{}' vm.swappiness=10
  [ "$status" -eq 0 ]
  [ "$(jq -c '.sysctl["vm.swappiness"]' <<<"$output")" = "10" ]
}

@test "edit_add_sysctl_pair: no '=' is a no-op (rc1, unchanged)" {
  run edit_add_sysctl_pair '{"a":1}' nonsense
  [ "$status" -eq 1 ]
  [ "$(jq -c . <<<"$output")" = '{"a":1}' ]
}

@test "edit_add_mirror_server: dedup-appends a Server URL" {
  local s; s="$(edit_add_mirror_server '{}' https://m.example/repo)"
  s="$(edit_add_mirror_server "$s" https://m.example/repo)"   # dup ignored
  [ "$(jq -c '.options.mirror_servers' <<<"$s")" \
    = '["https://m.example/repo"]' ]
}

@test "edit_add_mirror_server: empty URL is a no-op (rc1)" {
  run edit_add_mirror_server '{"a":1}' ""
  [ "$status" -eq 1 ]
  [ "$(jq -c . <<<"$output")" = '{"a":1}' ]
}

@test "edit_add_custom_repository: appends an object with defaulted signing" {
  run edit_add_custom_repository '{}' "myrepo https://r.example/x"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.options.custom_repositories[0]' <<<"$output")" \
    = '{"name":"myrepo","url":"https://r.example/x","sign_check":"Required","sign_option":"TrustedOnly"}' ]
}

@test "edit_add_custom_repository: fewer than 2 tokens is a no-op (rc1)" {
  run edit_add_custom_repository '{"a":1}' "onlyname"
  [ "$status" -eq 1 ]
  [ "$(jq -c . <<<"$output")" = '{"a":1}' ]
}
