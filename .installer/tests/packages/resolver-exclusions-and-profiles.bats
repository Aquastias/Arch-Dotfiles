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
  ! text_has_line "$packages" "fzf"
  ! text_has_line "$packages" "btop"
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
  # A config that touches every source.
  local config='{"users":["a"],"environment":
    {"desktop":["kde","niri","hyprland","umbriel"],"gpu":["amd"]},
     "options":{"bootloader":"grub"},
     "filesystem":"btrfs","packages":{"repo":{"c":["htop"]},
     "aur":{"m":["x"]}},"post_install":{"security":{"firewall":"ufw"},
     "backup":{"borg":true}}}'
  # Every source the resolver emits for it.
  emitted="$(package_resolver_resolve "$config" | cut -f1 | sort -u)"
  # everything emitted must be declared
  local source_name
  while IFS= read -r source_name; do
    text_has_line "$declared" "$source_name" || { echo "undeclared source: $source_name"; return 1; }
  done < <(printf '%s\n' "$emitted")
}


# ── the real committed profiles ─────────────────────────────────────────────

@test "the real desktop profile resolves through the resolver" {
  source "$INSTALLER_DIR/lib/config/profile-loader.sh"
  local effective; effective="$(profile_loader_load desktop)"
  run package_resolver_resolve "$effective"
  [ "$status" -eq 0 ]
  # The resolved package names (rows are source<TAB>layer<TAB>package).
  local packages; packages="$(printf '%s\n' "$output" | cut -f3 | sort -u)"
  text_has_line "$packages" "steam"   # core
  text_has_line "$packages" "qemu-full"   # desktop delta
  text_has_line "$packages" "plasma-meta"   # derived, KDE
  text_has_line "$packages" "base"   # derived, base list
}

# The curation's headline number: desktop adds exactly 25 packages over
# laptop, and laptop declares none of its own. (Was 31 before the dev
# toolchain moved to Host Core — both hosts are dev boxes.)
# desktop and laptop run identical software — every app lives in the Fleet
# Layer, so both profiles resolve to the same package set (ADR 0114, ADR 0157).
# They differ only in hardware/hostname/impermanence. The laptop-only
# hardware packages (LenovoLegionLinux) sit outside the comparison (ADR 0161).
@test "desktop and laptop resolve to the same package set (all apps in fleet)" {
  source "$INSTALLER_DIR/lib/config/profile-loader.sh"
  local desktop_packages laptop_packages
  desktop_packages="$(packages_of "$(profile_loader_load desktop)")"
  laptop_packages="$(packages_of "$(profile_loader_load laptop)")"
  source "$BATS_TEST_DIRNAME/../config/fleet-golden-helpers.bash"
  # The laptop's packages without its hardware-only ones.
  local hardware package
  local -a laptop_software=()
  hardware="$(printf '%s\n' "${FLEET_LAPTOP_HARDWARE_PACKAGES[@]}")"
  while IFS= read -r package; do
    text_has_line "$hardware" "$package" || laptop_software+=("$package")
  done < <(printf '%s\n' "$laptop_packages")
  laptop_packages="$(printf '%s\n' "${laptop_software[@]}")"
  [ "$(only_in_second "$laptop_packages" "$desktop_packages")" -eq 0 ]
  [ "$(only_in_second "$desktop_packages" "$laptop_packages")" -eq 0 ]
}

@test "a non-ZFS root reports no zfs-auto-snapshot" {
  local config='{"users":["a"],"filesystem":"ext4",
    "post_install":{"backup":{"zfs_auto_snapshot":true,"borg":true}}}'
  local bak; bak="$(packages_of "$config" backup)"
  text_has_line "$bak" "borg"
  ! text_has_line "$bak" "zfs-auto-snapshot"
}

@test "a manual layout reports no ZFS userland and no zfs-auto-snapshot" {
  local config='{"users":["a"],"disk_config":{"kind":"manual"},
    "post_install":{"backup":{"zfs_auto_snapshot":true}}}'
  [ -z "$(packages_of "$config" zfs)" ]
  [ -z "$(packages_of "$config" backup)" ]
}
