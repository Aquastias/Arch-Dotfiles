#!/usr/bin/env bats
# Tests: exclusions and real profiles (split from resolver.bats;
# shared setup in resolver-helpers.bash)

load resolver-helpers


# ── exclusions are reported separately ──────────────────────────────────────

@test "excluded packages are reported separately and are not installed" {
  local config='{"users":[],"packages":{"repo":{"cli":["htop"]},
                                      "exclude":["fzf","btop"]}}'
  run package_resolver_excluded "$config"
  [ "$output" = "$(printf 'btop\nfzf')" ]
  # and they are absent from the installed set
  local packages; packages="$(packages_of "$config")"
  ! grep -qx "fzf"  <<<"$packages"
  ! grep -qx "btop" <<<"$packages"
}

@test "a config with no exclusions reports none" {
  run package_resolver_excluded "$MIN"
  [ -z "$output" ]
}


# ── purity + determinism ────────────────────────────────────────────────────

@test "the resolver is deterministic for a given config" {
  local first_result second_result
  first_result="$(package_resolver_resolve "$MIN")"
  second_result="$(package_resolver_resolve "$MIN")"
  [ "$first_result" = "$second_result" ]
}

# The resolver must stay usable headless: every input is declarative, so it
# needs no package database and no network. Shadowing pacman and the network
# tools with stubs that ABORT proves it — if the resolver reached for any of
# them the run would fail loudly rather than silently degrade.
@test "the resolver makes no pacman or network call" {
  local bin; bin="$(mktemp -d)"
  local command
  for command in pacman pacman-key paru yay curl wget ping lspci pactree expac; do
    printf '#!/bin/sh\necho "FORBIDDEN: %s" >&2\nexit 127\n' "$command" > "$bin/$command"
    chmod +x "$bin/$command"
  done
  run env PATH="$bin:$PATH" INSTALLER_DIR="$INSTALLER_DIR" bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/package-resolver.sh'
    package_resolver_resolve '$MIN'"
  rm -rf "$bin"
  [ "$status" -eq 0 ]
  [[ "$output" != *FORBIDDEN* ]]
  [ -n "$output" ]
}

@test "package_resolver_sources lists every source the resolver can emit" {
  local declared emitted
  declared="$(package_resolver_sources | sort)"
  emitted="$(package_resolver_resolve '{"users":["a"],"environment":
    {"desktop":["kde"],"gpu":["amd"]},"options":{"bootloader":"grub"},
     "filesystem":"btrfs","packages":{"repo":{"c":["htop"]},
     "aur":{"m":["x"]}},"post_install":{"security":{"firewall":"ufw"},
     "backup":{"borg":true}}}' | awk -F'\t' '{ print $1 }' | sort -u)"
  # everything emitted must be declared
  local source_name
  while IFS= read -r source_name; do
    grep -qx "$source_name" <<<"$declared" || { echo "undeclared source: $source_name"; return 1; }
  done <<<"$emitted"
}


# ── the real committed profiles ─────────────────────────────────────────────

@test "the real desktop profile resolves through the resolver" {
  source "$INSTALLER_DIR/lib/config/profile-loader.sh"
  local effective; effective="$(profile_loader_load desktop)"
  run package_resolver_resolve "$effective"
  [ "$status" -eq 0 ]
  local packages; packages="$(awk -F'\t' '{ print $3 }' <<<"$output" | sort -u)"
  grep -qx "steam"       <<<"$packages"   # core
  grep -qx "qemu-full"   <<<"$packages"   # desktop delta
  grep -qx "plasma-meta" <<<"$packages"   # derived, KDE
  grep -qx "base"        <<<"$packages"   # derived, base list
}

# The curation's headline number: desktop adds exactly 25 packages over
# laptop, and laptop declares none of its own. (Was 31 before the dev
# toolchain moved to Host Core — both hosts are dev boxes.)
# desktop and laptop run identical software — every app lives in the Fleet
# Layer, so both profiles resolve to the same package set (ADR 0114, ADR 0157).
# They differ only in hardware/hostname/impermanence.
@test "desktop and laptop resolve to the same package set (all apps in fleet)" {
  source "$INSTALLER_DIR/lib/config/profile-loader.sh"
  local desktop_packages laptop_packages
  desktop_packages="$(package_resolver_resolve "$(profile_loader_load desktop)" | awk -F'\t' '{ print $3 }' | sort -u)"
  laptop_packages="$(package_resolver_resolve "$(profile_loader_load laptop)"  | awk -F'\t' '{ print $3 }' | sort -u)"
  [ "$(only_in_second "$laptop_packages" "$desktop_packages")" -eq 0 ]
  [ "$(only_in_second "$desktop_packages" "$laptop_packages")" -eq 0 ]
}

@test "a non-ZFS root reports no zfs-auto-snapshot" {
  local config='{"users":["a"],"filesystem":"ext4",
    "post_install":{"backup":{"zfs_auto_snapshot":true,"borg":true}}}'
  local bak; bak="$(packages_of "$config" backup)"
  grep -qx "borg" <<<"$bak"
  ! grep -qx "zfs-auto-snapshot" <<<"$bak"
}

@test "a manual layout reports no ZFS userland and no zfs-auto-snapshot" {
  local config='{"users":["a"],"disk_config":{"kind":"manual"},
    "post_install":{"backup":{"zfs_auto_snapshot":true}}}'
  [ -z "$(packages_of "$config" zfs)" ]
  [ -z "$(packages_of "$config" backup)" ]
}
