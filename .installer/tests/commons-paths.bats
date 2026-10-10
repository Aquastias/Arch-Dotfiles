#!/usr/bin/env bats
# Path helpers in every Commons world (ADR 0153 Tool Tiers): parent_directory
# and base_name replace raw dirname/basename. Each world carries its own copy
# (docs/agents/shell-commons.md), so every case runs against all three.

LIB="$BATS_TEST_DIRNAME/../lib"
WORLDS=(
  "$LIB/common.sh"               # Installer Stdlib
  "$LIB/chroot/chroot-common.sh" # chroot side
  "$LIB/shell/paths.sh"          # Shell Stdlib
)

# expect_in_every_world <expected> <command...>
expect_in_every_world() {
  local expected="$1" world
  shift
  for world in "${WORLDS[@]}"; do
    run bash -c 'source "$1"; shift; "$@"' _ "$world" "$@"
    [ "$status" -eq 0 ] || { echo "$world: status $status"; return 1; }
    [ "$output" = "$expected" ] \
      || { echo "$world: got '$output', want '$expected'"; return 1; }
  done
}

@test "parent_directory: nested path drops the last part" {
  expect_in_every_world /a/b parent_directory /a/b/c
}

@test "parent_directory: relative path" {
  expect_in_every_world a parent_directory a/b
}

@test "parent_directory: bare name is the current directory" {
  expect_in_every_world . parent_directory file
}

@test "parent_directory: top-level entry is root" {
  expect_in_every_world / parent_directory /file
}

@test "parent_directory: trailing slash is ignored" {
  expect_in_every_world /a parent_directory /a/b/
}

@test "parent_directory: root stays root" {
  expect_in_every_world / parent_directory /
}

@test "base_name: last part of a path" {
  expect_in_every_world c.sh base_name /a/b/c.sh
}

@test "base_name: trailing slash is ignored" {
  expect_in_every_world b base_name /a/b/
}

@test "base_name: bare name is itself" {
  expect_in_every_world file base_name file
}

@test "base_name: root stays root" {
  expect_in_every_world / base_name /
}

@test "base_name: strips an optional suffix" {
  expect_in_every_world b base_name /a/b.sh .sh
}
