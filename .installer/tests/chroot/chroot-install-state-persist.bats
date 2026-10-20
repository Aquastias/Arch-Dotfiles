#!/usr/bin/env bats
# Tests for install_config_persist_json — the .persist sub-object
# install_state_write writes, read from the effective config.

setup() {
  # shellcheck source=../../lib/config/install-config.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/install-config.sh"
}

@test "persist-state: empty dirs/files when host has no persist" {
  result="$(install_config_from_json '{}' persist_json)"
  [ "$(printf '%s' "$result" | jq -r '.directories | length')" = "0" ]
  [ "$(printf '%s' "$result" | jq -r '.files | length')" = "0" ]
}

@test "persist-state: passes directories and files through verbatim" {
  local host
  host='{"persist":{"directories":["/etc/wireguard"],"files":["/etc/foo"]}}'
  result="$(install_config_from_json "$host" persist_json)"
  [ "$(printf '%s' "$result" | jq -r '.directories[0]')" = "/etc/wireguard" ]
  [ "$(printf '%s' "$result" | jq -r '.files[0]')"       = "/etc/foo" ]
}

@test "persist-state: tolerates partial input (only directories)" {
  local host='{"persist":{"directories":["/etc/wireguard"]}}'
  result="$(install_config_from_json "$host" persist_json)"
  [ "$(printf '%s' "$result" | jq -r '.directories[0]')" = "/etc/wireguard" ]
  [ "$(printf '%s' "$result" | jq -r '.files | length')" = "0" ]
}
