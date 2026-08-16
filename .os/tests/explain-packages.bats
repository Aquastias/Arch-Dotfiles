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
  [[ "$output" == *"repo  (core+host,"* ]]
}

@test "explain-packages: reports a total count" {
  run bash "$TOOL" desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total:"* ]]
  local total
  total="$(sed -n 's/.*Total: \([0-9]*\) unique packages.*/\1/p' <<<"$output")"
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
  local t; t="$(mktemp -d)"
  mkdir -p "$t/hosts/core" "$t/hosts/handmade" "$t/users/core"
  printf '{"users":[],"system_programs":[]}\n' \
    > "$t/hosts/core/profile.jsonc"
  printf '{"shell":"/bin/zsh"}\n' > "$t/users/core/profile.jsonc"
  cat > "$t/hosts/handmade/profile.jsonc" <<'JSON'
{"users":["alice"],"options":{"kernel":["zen"],"bootloader":"grub"},
 "filesystem":"btrfs","environment":{"gpu":["amd"],"desktop":[]},
 "packages":{"repo":{"cli":["ripgrep"]}}}
JSON
  # the tool resolves against its own tree, so run it from a copy
  mkdir -p "$t/tools" "$t/lib"
  cp -r "$OS/lib/." "$t/lib/"
  cp "$OS/tools/explain-packages.sh" "$t/tools/"

  run bash "$t/tools/explain-packages.sh" handmade --flat
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "ripgrep"       # authored
  echo "$output" | grep -qx "linux-zen"     # derived from kernel
  echo "$output" | grep -qx "grub"          # derived from bootloader
  echo "$output" | grep -qx "btrfs-progs"   # derived from filesystem
  echo "$output" | grep -qx "vulkan-radeon" # derived from gpu
  echo "$output" | grep -qx "zsh"           # derived from the login shell
  ! echo "$output" | grep -qx "plasma-meta" # no desktop selected
  rm -rf "$t"
}

# cups is a toggle-derived System Program (ADR 0079): on by default, reported
# under the `printing` source; genuinely absent when the toggle is off.
@test "explain-packages: cups is the printing-derived source, toggle-gated" {
  local t; t="$(mktemp -d)"
  mkdir -p "$t/hosts/core" "$t/hosts/on" "$t/hosts/off" "$t/users/core" \
           "$t/tools" "$t/lib"
  printf '{"users":[],"system_programs":[]}\n' > "$t/hosts/core/profile.jsonc"
  printf '{"shell":"/bin/zsh"}\n' > "$t/users/core/profile.jsonc"
  # `on` leaves the toggle at its default (absent ⇒ on); `off` sets it false.
  printf '{"users":["alice"]}\n' > "$t/hosts/on/profile.jsonc"
  printf '{"users":["alice"],"options":{"printing":{"enabled":false}}}\n' \
    > "$t/hosts/off/profile.jsonc"
  cp -r "$OS/lib/." "$t/lib/"
  cp "$OS/tools/explain-packages.sh" "$t/tools/"

  run bash "$t/tools/explain-packages.sh" on --sources
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^ +printing +1$'
  run bash "$t/tools/explain-packages.sh" on --flat
  echo "$output" | grep -qx "cups"

  run bash "$t/tools/explain-packages.sh" off --flat
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qx "cups"
  rm -rf "$t"
}

@test "explain-packages: reports excluded entries separately" {
  local t; t="$(mktemp -d)"
  mkdir -p "$t/hosts/core" "$t/hosts/box" "$t/users/core" "$t/tools" "$t/lib"
  printf '{"users":[],"packages":{"repo":{"cli":["htop","fzf"]}}}\n' \
    > "$t/hosts/core/profile.jsonc"
  printf '{}\n' > "$t/users/core/profile.jsonc"
  # exclude survives on the AUTHORED profile, which is what the report reads
  printf '{"users":[],"packages":{"exclude":["fzf"]}}\n' \
    > "$t/hosts/box/profile.jsonc"
  cp -r "$OS/lib/." "$t/lib/"
  cp "$OS/tools/explain-packages.sh" "$t/tools/"

  # … and it is NAMED in an Excluded section, so the operator can confirm the
  # exclusion took effect. The Layer Resolver strips packages.exclude from a
  # resolved config, so the report reads the authored profile for this.
  run bash "$t/tools/explain-packages.sh" box
  [ "$status" -eq 0 ]
  [[ "$output" == *"Excluded by this profile (1)"* ]]
  [[ "$output" == *"fzf"* ]]

  # fzf is excluded, so it is not in the installed set …
  run bash "$t/tools/explain-packages.sh" box --flat
  ! echo "$output" | grep -qx "fzf"
  echo "$output" | grep -qx "htop"
  rm -rf "$t"
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
@test "explain-packages agrees with a direct pkgres_resolve call" {
  run bash "$TOOL" laptop --flat
  [ "$status" -eq 0 ]
  local direct
  direct="$(cd "$OS" && OS_DIR="$OS" bash -c '
    source lib/common.sh
    source lib/config/profile.sh
    source lib/packages/resolver.sh
    pkgres_resolve "$(load_profile laptop)" | cut -f3 | sort -u')"
  [ "$output" = "$direct" ]
}
