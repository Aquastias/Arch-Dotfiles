#!/usr/bin/env bats
# tools/explain-packages.sh — the CLI inspector over the Package Resolver.
#
# It must answer "what lands?" for a HAND-EDITED profile with no TUI
# involvement, and share its resolver with the menu's derived section so the
# two cannot drift.

setup() {
  OS="$BATS_TEST_DIRNAME/.."
  TOOL="$OS/tools/explain-packages.sh"
}

@test "explain-packages: takes a profile name and prints grouped output" {
  run bash "$TOOL" desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *"Resolved package set — profile: desktop"* ]]
  # grouped by source, with a layer + count per group
  [[ "$output" == *"base  (derived,"* ]]
  # desktop carries no packages delta — repo is the Fleet Layer (ADR 0157)
  [[ "$output" == *"repo  (fleet,"* ]]
}

@test "explain-packages: reports a total count" {
  run bash "$TOOL" desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total:"* ]]
  local total
  total="$(awk 'match($0, /Total: [0-9]* unique packages/) { $0 = substr($0, RSTART + 7, RLENGTH - 23); print }' <<<"$output")"
  [ "$total" -gt 100 ]
}

@test "explain-packages: --flat is one package per line, sorted and unique" {
  run bash "$TOOL" desktop --flat
  [ "$status" -eq 0 ]
  [ "$output" = "$(sort -u <<<"$output")" ]
  echo "$output" | grep -qx "steam"
  echo "$output" | grep -qx "plasma-meta"
}

@test "explain-packages: --sources lists each source with its count" {
  run bash "$TOOL" desktop --sources
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^ +base +[0-9]+$'
  echo "$output" | grep -qE '^ +repo +[0-9]+$'
}

# The whole point: no TUI, no installer, no VM.
@test "explain-packages: works on a hand-edited profile" {
  local test_directory; test_directory="$(mktemp -d)"
  mkdir -p "$test_directory/hosts/core" "$test_directory/hosts/handmade" "$test_directory/users/core"
  printf '{"users":[],"host_programs":[]}\n' \
    > "$test_directory/hosts/core/profile.jsonc"
  printf '{"shell":"/bin/zsh"}\n' > "$test_directory/users/core/profile.jsonc"
  cat > "$test_directory/hosts/handmade/profile.jsonc" <<'JSON'
{"users":["alice"],"options":{"kernel":["zen"],"bootloader":"grub"},
 "filesystem":"btrfs","environment":{"gpu":["amd"],"desktop":[]},
 "packages":{"repo":{"cli":["ripgrep"]}}}
JSON
  # the tool resolves against its own tree, so run it from a copy
  mkdir -p "$test_directory/tools" "$test_directory/lib"
  cp -r "$OS/lib/." "$test_directory/lib/"
  cp "$OS/tools/explain-packages.sh" "$test_directory/tools/"

  run bash "$test_directory/tools/explain-packages.sh" handmade --flat
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "ripgrep"       # authored
  echo "$output" | grep -qx "linux-zen"     # derived from kernel
  echo "$output" | grep -qx "grub"          # derived from bootloader
  echo "$output" | grep -qx "btrfs-progs"   # derived from filesystem
  echo "$output" | grep -qx "vulkan-radeon" # derived from gpu
  echo "$output" | grep -qx "zsh"           # derived from the login shell
  ! echo "$output" | grep -qx "plasma-meta" # no desktop selected
  rm -rf "$test_directory"
}

# cups is a toggle-derived System Program (ADR 0079): on by default, reported
# under the `printing` source; genuinely absent when the toggle is off.
@test "explain-packages: cups is the printing-derived source, toggle-gated" {
  local test_directory; test_directory="$(mktemp -d)"
  mkdir -p "$test_directory/hosts/core" "$test_directory/hosts/on" "$test_directory/hosts/off" "$test_directory/users/core" \
           "$test_directory/tools" "$test_directory/lib"
  printf '{"users":[],"host_programs":[]}\n' > "$test_directory/hosts/core/profile.jsonc"
  printf '{"shell":"/bin/zsh"}\n' > "$test_directory/users/core/profile.jsonc"
  # `on` leaves the toggle at its default (absent ⇒ on); `off` sets it false.
  printf '{"users":["alice"]}\n' > "$test_directory/hosts/on/profile.jsonc"
  printf '{"users":["alice"],"options":{"printing":{"enabled":false}}}\n' \
    > "$test_directory/hosts/off/profile.jsonc"
  cp -r "$OS/lib/." "$test_directory/lib/"
  cp "$OS/tools/explain-packages.sh" "$test_directory/tools/"

  run bash "$test_directory/tools/explain-packages.sh" on --sources
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^ +printing +1$'
  run bash "$test_directory/tools/explain-packages.sh" on --flat
  echo "$output" | grep -qx "cups"

  run bash "$test_directory/tools/explain-packages.sh" off --flat
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qx "cups"
  rm -rf "$test_directory"
}

@test "explain-packages: reports excluded entries separately" {
  local test_directory; test_directory="$(mktemp -d)"
  mkdir -p "$test_directory/hosts/core" "$test_directory/hosts/box" "$test_directory/users/core" "$test_directory/tools" "$test_directory/lib"
  printf '{"users":[],"packages":{"repo":{"cli":["htop","fzf"]}}}\n' \
    > "$test_directory/hosts/core/profile.jsonc"
  printf '{}\n' > "$test_directory/users/core/profile.jsonc"
  # exclude survives on the AUTHORED profile, which is what the report reads
  printf '{"users":[],"packages":{"exclude":["fzf"]}}\n' \
    > "$test_directory/hosts/box/profile.jsonc"
  cp -r "$OS/lib/." "$test_directory/lib/"
  cp "$OS/tools/explain-packages.sh" "$test_directory/tools/"

  # … and it is NAMED in an Excluded section, so the operator can confirm the
  # exclusion took effect. The Layer Resolver strips packages.exclude from a
  # resolved config, so the report reads the authored profile for this.
  run bash "$test_directory/tools/explain-packages.sh" box
  [ "$status" -eq 0 ]
  [[ "$output" == *"Excluded by this profile (1)"* ]]
  [[ "$output" == *"fzf"* ]]

  # fzf is excluded, so it is not in the installed set …
  run bash "$test_directory/tools/explain-packages.sh" box --flat
  ! echo "$output" | grep -qx "fzf"
  echo "$output" | grep -qx "htop"
  rm -rf "$test_directory"
}

# `auto` and the CPU microcode need the target hardware, so they are reported
# as unresolved rather than emitted as fake package names in --flat.
@test "explain-packages: reports what is resolved at install time" {
  run bash "$TOOL" desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *"Resolved at install time"* ]]
  [[ "$output" == *"lspci"* ]]
  [[ "$output" == *"microcode"* ]]

  run bash "$TOOL" desktop --flat
  ! echo "$output" | grep -q "auto —"
  ! echo "$output" | grep -q "("
}

@test "explain-packages: no argument prints usage and the profile list" {
  run bash "$TOOL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"desktop"* ]]
  [[ "$output" == *"laptop"* ]]
}

# The inspector and the menu's derived section must agree — same resolver.
@test "explain-packages agrees with a direct package_resolver_resolve call" {
  run bash "$TOOL" laptop --flat
  [ "$status" -eq 0 ]
  local direct
  direct="$(cd "$OS" && INSTALLER_DIR="$OS" bash -c '
    source lib/common.sh
    source lib/config/profile-loader.sh
    source lib/packages/package-resolver.sh
    package_resolver_resolve "$(profile_loader_load laptop)" | cut -f3 | sort -u')"
  [ "$output" = "$direct" ]
}

# A profile with no file resolves Host Core alone (the loader's status 1),
# says so on stderr, and still reports — it is not a hard failure.
@test "explain-packages: a missing profile reports Host Core only" {
  run bash "$TOOL" no-such-profile --flat
  [ "$status" -eq 0 ]
  [[ "$output" == *"no profile 'no-such-profile' — resolved core only."* ]]
  grep -qx base <<<"$output"
}

# Host Programs and each user's User Programs land too (ADR 0157), so the
# report covers the whole install, not only the package slots.
@test "explain-packages: reports Host Programs and User Programs" {
  run bash "$TOOL" desktop --flat
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "lact"     # a Fleet Layer base Host Program
  echo "$output" | grep -qx "claude"   # a User Program of aquastias
  echo "$output" | grep -qx "docker"   # a User Program of aquastias
}

@test "explain-packages: --sources lists host-programs and user-programs" {
  run bash "$TOOL" desktop --sources
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^ +host-programs +[0-9]+$'
  echo "$output" | grep -qE '^ +user-programs +[0-9]+$'
}

@test "explain-packages: a bare profile reports no User Programs" {
  run bash "$TOOL" minimal --flat
  [ "$status" -eq 0 ]
  grep -qx "claude" <<<"$output" && return 1
  grep -qx "lact" <<<"$output" && return 1
  return 0
}
