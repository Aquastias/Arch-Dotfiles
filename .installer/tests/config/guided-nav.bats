#!/usr/bin/env bats
# Tests for .installer/lib/config/navigation.sh — the Guided Installer's navigation
# state
# (ADR 0042). Pure JSON-in/JSON-out screen transitions for the persistent-fzf
# controller; behaviour asserted through the public verbs (screen + fields out).

setup() { source "$BATS_TEST_DIRNAME/../../lib/config/navigation.sh"; }

@test "navigation_new: starts on the top screen" {
  [ "$(navigation_screen "$(navigation_new)")" = "top" ]
}

@test "navigation_to_category: enters a category, screen + category set" {
  local navigation; navigation="$(navigation_to_category Disks)"
  [ "$(navigation_screen "$navigation")" = "category" ]
  [ "$(navigation_get "$navigation" category)" = "Disks" ]
}

@test "navigation_to_values: carries category, field, label" {
  local navigation; navigation="$(navigation_to_values Disks options.encryption encryption)"
  [ "$(navigation_screen "$navigation")" = "values" ]
  [ "$(navigation_get "$navigation" category)" = "Disks" ]
  [ "$(navigation_get "$navigation" field)" = "options.encryption" ]
  [ "$(navigation_get "$navigation" label)" = "encryption" ]
}

@test "navigation_to_text: carries category, field, label" {
  local navigation; navigation="$(navigation_to_text System system.hostname hostname)"
  [ "$(navigation_screen "$navigation")" = "text" ]
  [ "$(navigation_get "$navigation" field)" = "system.hostname" ]
}

@test "navigation_get: absent key is empty" {
  [ -z "$(navigation_get "$(navigation_new)" category)" ]
}

@test "navigation_back: values → its category" {
  local navigation; navigation="$(navigation_back "$(navigation_to_values Disks options.swap swap)")"
  [ "$(navigation_screen "$navigation")" = "category" ]
  [ "$(navigation_get "$navigation" category)" = "Disks" ]
}

@test "navigation_back: text → its category" {
  local navigation; navigation="$(navigation_back "$(navigation_to_text System system.hostname hostname)")"
  [ "$(navigation_screen "$navigation")" = "category" ]
  [ "$(navigation_get "$navigation" category)" = "System" ]
}

@test "navigation_back: category → top" {
  [ "$(navigation_screen "$(navigation_back "$(navigation_to_category Kernels)")")" = "top" ]
}

@test "navigation_back: top stays top" {
  [ "$(navigation_screen "$(navigation_back "$(navigation_new)")")" = "top" ]
}

@test "navigation_to_data_pools: enters the data-pools editor, back → category" {
  local navigation; navigation="$(navigation_to_data_pools Disks)"
  [ "$(navigation_screen "$navigation")" = "datapools" ]
  [ "$(navigation_screen "$(navigation_back "$navigation")")" = "category" ]
}

@test "navigation_to_pool_edit: carries the index, back → datapools" {
  local navigation; navigation="$(navigation_to_pool_edit Disks 1)"
  [ "$(navigation_screen "$navigation")" = "pooledit" ]
  [ "$(navigation_get "$navigation" index)" = "1" ]
  [ "$(navigation_screen "$(navigation_back "$navigation")")" = "datapools" ]
}
