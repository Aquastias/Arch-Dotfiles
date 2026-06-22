#!/usr/bin/env bats
# Tests for .os/lib/config/nav.sh — the Guided Installer's navigation state
# (ADR 0042). Pure JSON-in/JSON-out screen transitions for the persistent-fzf
# controller; behaviour asserted through the public verbs (screen + fields out).

setup() { source "$BATS_TEST_DIRNAME/../../lib/config/nav.sh"; }

@test "nav_new: starts on the top screen" {
  [ "$(nav_screen "$(nav_new)")" = "top" ]
}

@test "nav_to_category: enters a category, screen + category set" {
  local n; n="$(nav_to_category Disks)"
  [ "$(nav_screen "$n")" = "category" ]
  [ "$(nav_get "$n" category)" = "Disks" ]
}

@test "nav_to_values: carries category, field, label" {
  local n; n="$(nav_to_values Disks options.encryption encryption)"
  [ "$(nav_screen "$n")" = "values" ]
  [ "$(nav_get "$n" category)" = "Disks" ]
  [ "$(nav_get "$n" field)" = "options.encryption" ]
  [ "$(nav_get "$n" label)" = "encryption" ]
}

@test "nav_to_text: carries category, field, label" {
  local n; n="$(nav_to_text Host system.hostname hostname)"
  [ "$(nav_screen "$n")" = "text" ]
  [ "$(nav_get "$n" field)" = "system.hostname" ]
}

@test "nav_get: absent key is empty" {
  [ -z "$(nav_get "$(nav_new)" category)" ]
}

@test "nav_back: values → its category" {
  local n; n="$(nav_back "$(nav_to_values Disks options.swap swap)")"
  [ "$(nav_screen "$n")" = "category" ]
  [ "$(nav_get "$n" category)" = "Disks" ]
}

@test "nav_back: text → its category" {
  local n; n="$(nav_back "$(nav_to_text Host system.hostname hostname)")"
  [ "$(nav_screen "$n")" = "category" ]
  [ "$(nav_get "$n" category)" = "Host" ]
}

@test "nav_back: category → top" {
  [ "$(nav_screen "$(nav_back "$(nav_to_category Options)")")" = "top" ]
}

@test "nav_back: top stays top" {
  [ "$(nav_screen "$(nav_back "$(nav_new)")")" = "top" ]
}
