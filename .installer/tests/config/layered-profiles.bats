#!/usr/bin/env bats
# End-to-end regression over the COMMITTED profiles (ADR 0056/0057).
#
# Resolves the real `core`, `desktop`, `laptop` and VM-fixture profiles through
# the Layer Resolver and asserts the final sets, so a curation mistake fails in
# seconds here rather than in a VM install. This also pins the invariants the
# curation established:
#   - laptop contributes no packages of its own
#   - no Program name appears in any package list
#   - nothing declared duplicates what a derived set already provides
#   - the VM fixtures resolve lean, with no workstation userland

setup() {
  export INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."
  source "$INSTALLER_DIR/lib/config/profile-loader.sh"
  source "$INSTALLER_DIR/lib/config/layer-resolver.sh"
  source "$INSTALLER_DIR/lib/config/program-registry.sh"
  program_registry_build
}

# repo_of <profile> / aur_of <profile> — the resolved flat package set.
repo_of() { profile_loader_load "$1" | jq -r '.packages.repo // {}
  | to_entries[].value[]' | sort -u; }
aur_of()  { profile_loader_load "$1" | jq -r '.packages.aur // {}
  | to_entries[].value[]' | sort -u; }
fleet_repo() { jsonc_strip "$INSTALLER_DIR/hosts/fleet/profile.jsonc" \
  | jq -r '.packages.repo | to_entries[].value[]' | sort -u; }

# ── the committed profiles resolve ──────────────────────────────────────────

@test "core, desktop and laptop all resolve without error" {
  local host
  for host in desktop laptop; do
    run profile_loader_load "$host"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e . >/dev/null
  done
}

@test "laptop resolves to exactly the Fleet Layer's package set" {
  # laptop declares no packages, so its resolved set IS the Fleet Layer's
  # (ADR 0157) — one software image for the fleet.
  [ "$(repo_of laptop)" = "$(fleet_repo)" ]
}

# desktop carries no packages delta — all apps live in the Fleet Layer (ADR
# 0114, ADR 0157), so its repo set equals the Fleet Layer's exactly.
@test "desktop resolves to the Fleet Layer's repo set, no delta of its own" {
  local desktop_packages fleet
  desktop_packages="$(repo_of desktop)"; fleet="$(fleet_repo)"
  local package
  while IFS= read -r package; do
    grep -qx "$package" <<<"$desktop_packages" || { echo "fleet package missing: $package"; return 1; }
  done <<<"$fleet"
  [ "$(printf '%s\n' "$desktop_packages" | sort -u)" = "$(printf '%s\n' "$fleet" | sort -u)" ]
}

@test "desktop's delta packages land in the resolved set" {
  local desktop_packages; desktop_packages="$(repo_of desktop)"
  local package
  for package in qemu-full libguestfs virt-viewer lutris wine tectonic dnsmasq; do
    grep -qx "$package" <<<"$desktop_packages" || { echo "missing desktop delta: $package"; return 1; }
  done
}

@test "Fleet Layer packages reach both machines" {
  local package host
  for host in desktop laptop; do
    local packages; packages="$(repo_of "$host")"
    for package in firefox steam htop gimp vlc; do
      grep -qx "$package" <<<"$packages" || { echo "$host missing fleet pkg: $package"; return 1; }
    done
  done
}

# aur lives entirely in the Fleet Layer too (ADR 0114, ADR 0157), so both
# machines get it.
@test "aur resolves from the Fleet Layer on both machines" {
  local desktop_aur laptop_aur
  desktop_aur="$(aur_of desktop)"; laptop_aur="$(aur_of laptop)"
  local package
  # ttf-ms-fonts left the core AUR list for the options.fonts Font Catalog (ADR
  # 0080) — it is routed to the paru pass by the font resolver, not packages.aur.
  for package in rar zen-browser-bin runelite; do
    grep -qx "$package" <<<"$desktop_aur" || { echo "desktop missing fleet aur: $package"; return 1; }
    grep -qx "$package" <<<"$laptop_aur" || { echo "laptop missing core aur: $package"; return 1; }
  done
}

# ── no Program name appears in any package list ─────────────────────────────

@test "no Program name appears in any committed package list" {
  local host packages package
  for host in desktop laptop; do
    packages="$(repo_of "$host"; aur_of "$host")"
    while IFS= read -r package; do
      [[ -n "$package" ]] || continue
      [ "$(program_registry_kind "$package")" = "none" ] \
        || { echo "$host: '$package' is a Program, not a package"; return 1; }
    done <<<"$packages"
  done
}

# The three live violations the curation removed.
@test "docker, virt-manager and teamspeak3 are gone from both hosts" {
  local host package
  for host in desktop laptop; do
    local packages; packages="$(repo_of "$host"; aur_of "$host")"
    for package in docker docker-compose virt-manager teamspeak3; do
      ! grep -qx "$package" <<<"$packages" || { echo "$host still declares $package"; return 1; }
    done
  done
}

# ── nothing declared duplicates a derived set ───────────────────────────────

@test "no declared package duplicates the Base Package List" {
  local host package packages
  for host in desktop laptop; do
    packages="$(repo_of "$host")"
    for package in base base-devel linux-firmware networkmanager openssh cronie \
             efibootmgr dosfstools vim git sudo rsync jq pacman-contrib \
             man-db man-pages texinfo stow; do
      ! grep -qx "$package" <<<"$packages" \
        || { echo "$host re-declares base package: $package"; return 1; }
    done
  done
}

@test "no declared package duplicates the derived audio set" {
  local host package packages
  for host in desktop laptop; do
    packages="$(repo_of "$host")"
    for package in pipewire pipewire-pulse pipewire-alsa wireplumber \
             gst-plugin-pipewire pipewire-jack libpulse; do
      ! grep -qx "$package" <<<"$packages" \
        || { echo "$host re-declares derived audio package: $package"; return 1; }
    done
  done
}

@test "no declared package duplicates a derived filesystem tool or shell" {
  local host package packages
  for host in desktop laptop; do
    packages="$(repo_of "$host")"
    for package in btrfs-progs xfsprogs zsh; do
      ! grep -qx "$package" <<<"$packages" \
        || { echo "$host re-declares derived package: $package"; return 1; }
    done
  done
}

@test "no declared package duplicates a KDE-adapter package" {
  local host package packages
  for host in desktop laptop; do
    packages="$(repo_of "$host")"
    for package in papirus-icon-theme qt5-wayland qt6-wayland xdg-utils sddm-kcm \
             konsole dolphin ark okular kate; do
      ! grep -qx "$package" <<<"$packages" \
        || { echo "$host re-declares DE-adapter package: $package"; return 1; }
    done
  done
}

# ── everything CURATION.md marked drop is gone ──────────────────────────────

@test "every dropped package is absent from every committed profile" {
  local host package packages
  for host in desktop laptop; do
    packages="$(repo_of "$host"; aur_of "$host"; fleet_repo)"
    for package in zram-generator uwsm nftables iptables wireless_tools less zed \
             flatpak libavif qemu-base vde2 cpio zinit qt6ct-kde \
             btop-theme-catppuccin catppuccin-cursors-mocha \
             catppuccin-gtk-theme-mocha catppuccin-sddm-theme-mocha \
             catppuccin-plasma-colorscheme-mocha \
             catppuccin-konsole-colorscheme-mocha-git \
             papirus-folders-catppuccin-git \
             plymouth-theme-catppuccin-mocha-git; do
      ! grep -qx "$package" <<<"$packages" || { echo "$host still declares $package"; return 1; }
    done
  done
}

@test "no catppuccin package survives anywhere" {
  local host
  for host in core fleet desktop laptop; do
    ! grep -q "catppuccin" "$INSTALLER_DIR/hosts/$host/profile.jsonc" \
      || { echo "$host still declares a catppuccin package"; return 1; }
  done
}

# ── the VM fixtures resolve lean ────────────────────────────────────────────

@test "the VM fixtures inherit no packages from Host Core" {
  local host
  for host in arch-data arch-kde arch-secure; do
    run profile_loader_load "$host"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '(.packages.repo // {}) == {}'
    echo "$output" | jq -e '(.packages.aur // {}) == {}'
  done
}

@test "the VM fixtures pull in no workstation userland" {
  local host package packages
  for host in arch-data arch-kde arch-secure; do
    packages="$(repo_of "$host")"
    for package in steam firefox gimp discord wine lutris kitty; do
      ! grep -qx "$package" <<<"$packages" \
        || { echo "$host pulled workstation package: $package"; return 1; }
    done
  done
}

# inherit is scoped to packages — the fixtures still get core's users/sysctl.
# cups is no longer among core's system programs (ADR 0079): it is
# toggle-derived and injected at assembly, so the loaded profile inherits no
# system programs from core here.
@test "the VM fixtures still inherit Host Core's sysctl" {
  local host
  for host in arch-data arch-kde arch-secure; do
    run profile_loader_load "$host"
    echo "$output" | jq -e '.sysctl["vm.swappiness"] == 10'
    echo "$output" | jq -e '.host_programs | index("cups") | not'
  done
}

# ── promoted base host programs (ADR 0089) ──────────────────────────────────
# Packages the installer once pacstrapped bare, now kind:host Programs with a
# single home: absent from packages.repo, present in host_programs on the real
# hosts, and dropped on the bare inherit:false profiles.

host_programs_of() { profile_loader_load "$1" | jq -r '.host_programs // [] | .[]'; }

@test "promoted base host programs resolve into host_programs, not packages" {
  local host package packages host_programs
  for host in desktop laptop; do
    packages="$(repo_of "$host")"; host_programs="$(host_programs_of "$host")"
    for package in ccache fwupd lact smartmontools; do
      grep -qx "$package" <<<"$host_programs" \
        || { echo "$host missing host program: $package"; return 1; }
      ! grep -qx "$package" <<<"$packages" \
        || { echo "$host still declares $package as a package"; return 1; }
    done
  done
}

# inherit:false drops the lower layer's host_programs as well as its packages
# (ADR 0089), so every bare profile (the lean VM fixtures AND minimal) opts out
# of the base host programs in one place — no per-profile exclude list.
@test "the inherit:false profiles inherit no host_programs from Host Core" {
  local host package host_programs
  for host in arch-data arch-kde arch-secure minimal; do
    host_programs="$(host_programs_of "$host")"
    for package in ccache fwupd lact smartmontools; do
      ! grep -qx "$package" <<<"$host_programs" \
        || { echo "$host wrongly inherited host program: $package"; return 1; }
    done
  done
}

# ── the user layer ──────────────────────────────────────────────────────────

@test "a real user inherits User Core's programs and zsh shell" {
  run profile_loader_load_user aquastias
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.programs | index("docker")'
  echo "$output" | jq -e '.programs | index("virt-manager")'
  echo "$output" | jq -e '.shell == "/bin/zsh"'
}

@test "the throwaway test users exclude User Core's programs" {
  local user
  for user in test data; do
    run profile_loader_load_user "$user"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.programs | index("docker") | not'
    echo "$output" | jq -e '.programs | index("virt-manager") | not'
  done
}

@test "the bare server user (programs_inherit:false) inherits no programs" {
  # ADR 0134: minimal's server user drops User Core's programs wholesale via one
  # flag — the user-layer twin of packages.inherit:false.
  run profile_loader_load_user server
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.programs // []) == []'
  echo "$output" | jq -e '.programs | index("kitty") | not'
  echo "$output" | jq -e '.programs | index("claude") | not'
  # the control key is stripped from the resolved profile
  echo "$output" | jq -e 'has("programs_inherit") | not'
}

@test "the control keys never reach a resolved profile" {
  local host
  for host in desktop laptop arch-kde; do
    run profile_loader_load "$host"
    echo "$output" | jq -e '(.packages // {}) | has("inherit") | not'
    echo "$output" | jq -e '(.packages // {}) | has("exclude") | not'
    echo "$output" | jq -e 'has("host_programs_exclude") | not'
  done
  run profile_loader_load_user test
  echo "$output" | jq -e 'has("programs_exclude") | not'
}
