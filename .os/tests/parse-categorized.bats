#!/usr/bin/env bats
# Tests for lib/categorized-list.sh — Categorized List Parser.
#
# Pure function. Input: JSON string + leaf type. Output: sorted, deduped
# flat list on stdout. Fails via lib/common.sh::error on shape, leaf-type,
# or category-name violations.

setup() {
  # shellcheck source=../lib/common.sh
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  # shellcheck source=../lib/categorized-list.sh
  source "$BATS_TEST_DIRNAME/../lib/categorized-list.sh"
}

@test "string mode: valid 2-level object yields sorted-unique flat list" {
  run categorized_list_parse \
    '{"browsers":["firefox"],"dev":["git","go","neovim"]}' \
    string packages.repo
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'firefox\ngit\ngo\nneovim')" ]
}

@test "string mode: duplicates across categories are deduped" {
  run categorized_list_parse \
    '{"browsers":["firefox"],"web":["firefox","curl"]}' \
    string packages.repo
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'curl\nfirefox')" ]
}

@test "string mode: empty category contributes nothing, no error" {
  run categorized_list_parse \
    '{"browsers":["firefox"],"empty":[]}' \
    string packages.repo
  [ "$status" -eq 0 ]
  [ "$output" = "firefox" ]
}

@test "string mode: empty top-level object yields empty output" {
  run categorized_list_parse '{}' string packages.repo
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bool mode: mixed true/false emits only true keys" {
  run categorized_list_parse \
    '{"plasma-extras":{"sddm-kcm":true,"kimageformats5":false},
      "file-management":{"dolphin":true}}' \
    bool apps_list
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'dolphin\nsddm-kcm')" ]
}

@test "bool mode: all false yields empty output" {
  run categorized_list_parse \
    '{"plasma-extras":{"sddm-kcm":false,"kimageformats5":false}}' \
    bool apps_list
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "invalid: top-level array → error names 'expected object'" {
  run categorized_list_parse '["firefox","git"]' string packages.repo
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"packages.repo"* ]]
  [[ "$output$stderr" == *"object"* ]]
}

@test "invalid: depth 1 (string leaf at category slot) → error names path" {
  run categorized_list_parse \
    '{"browsers":"firefox"}' string packages.repo
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"packages.repo.browsers"* ]]
  [[ "$output$stderr" == *"array"* ]]
}

@test "invalid: depth 3 (object inside string-mode array) → error names path" {
  run categorized_list_parse \
    '{"browsers":["firefox",{"nested":true}]}' string packages.repo
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"packages.repo.browsers"* ]]
  [[ "$output$stderr" == *"string"* ]]
}

@test "invalid: category 'Browsers' (uppercase) → error names rejected key" {
  run categorized_list_parse \
    '{"Browsers":["firefox"]}' string packages.repo
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"Browsers"* ]]
}

@test "invalid: category 'media_apps' (underscore) → error names rejected key" {
  run categorized_list_parse \
    '{"media_apps":["vlc"]}' string packages.repo
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"media_apps"* ]]
}

@test "invalid: category 'bad!' (punctuation) → error names rejected key" {
  run categorized_list_parse \
    '{"bad!":["x"]}' string packages.repo
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"bad!"* ]]
}

@test "invalid: string mode with boolean leaf → error names path and type" {
  run categorized_list_parse \
    '{"browsers":["firefox", true]}' string packages.repo
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"packages.repo.browsers"* ]]
  [[ "$output$stderr" == *"string"* ]]
}

@test "invalid: bool mode with string leaf → error names path and type" {
  run categorized_list_parse \
    '{"plasma-extras":{"sddm-kcm":"yes"}}' bool apps_list
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"apps_list.plasma-extras.sddm-kcm"* ]]
  [[ "$output$stderr" == *"boolean"* ]]
}
