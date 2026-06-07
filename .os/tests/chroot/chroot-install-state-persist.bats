#!/usr/bin/env bats
# Tests for _install_state_persist_obj() — builds the .persist sub-object
# of install-state.json from a merged host config JSON.

setup() {
  # shellcheck source=../../lib/install-state.sh
  source "$BATS_TEST_DIRNAME/../../lib/install-state.sh"
}

@test "persist-state: empty dirs/files when host has no persist" {
  result="$(_install_state_persist_obj '{}')"
  [ "$(printf '%s' "$result" | jq -r '.directories | length')" = "0" ]
  [ "$(printf '%s' "$result" | jq -r '.files | length')" = "0" ]
}

@test "persist-state: passes directories and files through verbatim" {
  local host
  host='{"persist":{"directories":["/etc/wireguard"],"files":["/etc/foo"]}}'
  result="$(_install_state_persist_obj "$host")"
  [ "$(printf '%s' "$result" | jq -r '.directories[0]')" = "/etc/wireguard" ]
  [ "$(printf '%s' "$result" | jq -r '.files[0]')"       = "/etc/foo" ]
}

@test "persist-state: tolerates partial input (only directories)" {
  local host='{"persist":{"directories":["/etc/wireguard"]}}'
  result="$(_install_state_persist_obj "$host")"
  [ "$(printf '%s' "$result" | jq -r '.directories[0]')" = "/etc/wireguard" ]
  [ "$(printf '%s' "$result" | jq -r '.files | length')" = "0" ]
}
