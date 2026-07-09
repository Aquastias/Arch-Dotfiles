#!/usr/bin/env bats
# Tests for the pool-group reference (kind, index) — issue 01 prefactor. The
# pool editor addresses ANY group (os_pool singleton, storage_groups[i],
# data_pools[i]) through one uniform reference instead of a bare data_pools
# index. Pure resolvers: state JSON + kind + index in, group JSON / new state
# out. No fzf, no tty.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/nav.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/edits.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
  source "$BATS_TEST_DIRNAME/../../lib/guided-controller.sh"

  STATE='{"mode":"multi",
          "os_pool":{"pool_name":"rpool","topology":"mirror","disk_count":2},
          "storage_groups":[{"name":"data","topology":"raidz1","disk_count":3}],
          "data_pools":[{"name":"tank0","topology":"mirror","disk_count":2},
                        {"name":"tank1","topology":"stripe","disk_count":1}]}'
}

# ── nav carries the kind ─────────────────────────────────────────────────────

@test "nav_to_pooledit: kind defaults to data when omitted" {
  [ "$(nav_get "$(nav_to_pooledit Disks 0)" kind)" = "data" ]
}

@test "nav_to_pooledit: carries an explicit group kind" {
  local p; p="$(nav_to_pooledit Disks 2 storage)"
  [ "$(nav_get "$p" kind)" = "storage" ]
  [ "$(nav_get "$p" index)" = "2" ]
  [ "$(nav_get "$(nav_to_pooledit Disks 0 os)" kind)" = "os" ]
}

@test "_ctl_pool_kind: reads the nav kind, defaulting to data" {
  [ "$(_ctl_pool_kind "$(nav_to_pooledit Disks 0)")" = "data" ]
  [ "$(_ctl_pool_kind "$(nav_to_pooledit Disks 0 os)")" = "os" ]
}

# ── _ctl_pool_get: resolve the group object for a (kind, index) ──────────────

@test "_ctl_pool_get: os resolves the singleton os_pool" {
  [ "$(_ctl_pool_get "$STATE" os 0 | jq -r '.pool_name')" = "rpool" ]
}

@test "_ctl_pool_get: storage resolves storage_groups[i]" {
  [ "$(_ctl_pool_get "$STATE" storage 0 | jq -r '.name')" = "data" ]
  [ "$(_ctl_pool_get "$STATE" storage 0 | jq -r '.topology')" = "raidz1" ]
}

@test "_ctl_pool_get: data resolves data_pools[i]" {
  [ "$(_ctl_pool_get "$STATE" data 1 | jq -r '.name')" = "tank1" ]
}

# ── _ctl_pool_set: replace the group, leaving siblings untouched ─────────────

@test "_ctl_pool_set: os replaces the os_pool" {
  local g='{"pool_name":"rpool","topology":"raidz1","disk_count":3}'
  local s; s="$(_ctl_pool_set "$STATE" os 0 "$g")"
  [ "$(jq -r '.os_pool.topology' <<<"$s")" = "raidz1" ]
  [ "$(jq -r '.data_pools[0].name' <<<"$s")" = "tank0" ]
}

@test "_ctl_pool_set: data replaces one pool, siblings intact" {
  local g='{"name":"tank0","topology":"stripe","disk_count":5}'
  local s; s="$(_ctl_pool_set "$STATE" data 0 "$g")"
  [ "$(jq -r '.data_pools[0].topology' <<<"$s")" = "stripe" ]
  [ "$(jq -r '.data_pools[1].name' <<<"$s")" = "tank1" ]
}

# ── _ctl_pool_del: remove data/storage; os is not removable ─────────────────

@test "_ctl_pool_del: data removes the pool" {
  local s; s="$(_ctl_pool_del "$STATE" data 0)"
  [ "$(jq '.data_pools | length' <<<"$s")" = "1" ]
  [ "$(jq -r '.data_pools[0].name' <<<"$s")" = "tank1" ]
}

@test "_ctl_pool_del: storage removes the group" {
  local s; s="$(_ctl_pool_del "$STATE" storage 0)"
  [ "$(jq '.storage_groups | length' <<<"$s")" = "0" ]
}

@test "_ctl_pool_del: os pool is not removable (no-op)" {
  local s; s="$(_ctl_pool_del "$STATE" os 0)"
  [ "$(jq -r '.os_pool.pool_name' <<<"$s")" = "rpool" ]
}
