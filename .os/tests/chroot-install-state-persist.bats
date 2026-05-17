#!/usr/bin/env bats
# Tests for _chroot_persist_state_obj() — builds the .persist sub-object
# of install-state.json from a merged host config JSON.

setup() {
  # shellcheck source=../lib/chroot.sh
  # Source-time deps (only need one fn; file must load cleanly).
  error()   { echo "ERROR: $*" >&2; exit 1; }
  info()    { :; }
  warn()    { :; }
  section() { :; }
  export -f error info warn section
  # Minimal stubs for anything chroot.sh references at source time.
  cfg()  { :; }
  cfgo() { :; }
  export -f cfg cfgo
  source "$BATS_TEST_DIRNAME/../lib/chroot.sh"
}

@test "persist-state: empty dirs/files when host has no persist" {
  result="$(_chroot_persist_state_obj '{}')"
  [ "$(printf '%s' "$result" | jq -r '.directories | length')" = "0" ]
  [ "$(printf '%s' "$result" | jq -r '.files | length')" = "0" ]
}

@test "persist-state: passes directories and files through verbatim" {
  local host
  host='{"persist":{"directories":["/etc/wireguard"],"files":["/etc/foo"]}}'
  result="$(_chroot_persist_state_obj "$host")"
  [ "$(printf '%s' "$result" | jq -r '.directories[0]')" = "/etc/wireguard" ]
  [ "$(printf '%s' "$result" | jq -r '.files[0]')"       = "/etc/foo" ]
}

@test "persist-state: tolerates partial input (only directories)" {
  local host='{"persist":{"directories":["/etc/wireguard"]}}'
  result="$(_chroot_persist_state_obj "$host")"
  [ "$(printf '%s' "$result" | jq -r '.directories[0]')" = "/etc/wireguard" ]
  [ "$(printf '%s' "$result" | jq -r '.files | length')" = "0" ]
}
