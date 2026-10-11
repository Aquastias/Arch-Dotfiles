#!/usr/bin/env bats
# Tests for the shared pure package maps (base / gpu / audio / filesystem) and
# the DRIFT GUARD that locks them: the same names must reach both callers — the
# install path (package_list_collect / environment_resolve) and the Package
# Resolver (package_resolver_resolve). A future re-hardcode in either caller
# fails here, not in a VM. gpu is pinned to an explicit vendor so the guard
# stays deterministic and headless (no lspci).

setup() {
  export INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."
  TEST_DIR="$(mktemp -d)"
  CONFIG_FILE="$TEST_DIR/install.json"
  export CONFIG_FILE
  source "$INSTALLER_DIR/lib/common.sh"
  source "$INSTALLER_DIR/lib/config/install-config.sh"
  source "$INSTALLER_DIR/lib/packages/base.sh"
  source "$INSTALLER_DIR/lib/packages/gpu.sh"
  source "$INSTALLER_DIR/lib/packages/audio.sh"
  source "$INSTALLER_DIR/lib/packages/filesystem.sh"
  source "$INSTALLER_DIR/lib/packages/package-list.sh"
  source "$INSTALLER_DIR/lib/config/environment.sh"
  source "$INSTALLER_DIR/lib/packages/package-resolver.sh"
  # Keep gpu resolution deterministic even if a test uses intel/auto.
  _environment_gpu_lspci_output() { printf ''; }
}

teardown() { rm -rf "$TEST_DIR"; }

write_config() { printf '%s\n' "$1" >"$CONFIG_FILE"; }
resolved_from_source() { package_resolver_resolve "$1" | awk -F'\t' -v s="$2" '$1==s{print $3}' | sort -u; }

# ── unit: base ──────────────────────────────────────────────────────────────

@test "base_packages: the unconditional 18-package set" {
  run base_packages
  [ "$status" -eq 0 ]
  [ "$(base_packages | sort -u | awk 'END { print NR }')" -eq 18 ]
  base_packages | grep -qx base
  base_packages | grep -qx base-devel
  base_packages | grep -qx stow
  base_packages | grep -qx texinfo
}

# ── unit: gpu ───────────────────────────────────────────────────────────────

@test "gpu_vendor_packages: amd / nvidia / intel-default / vm" {
  [ "$(gpu_vendor_packages amd)" = "vulkan-radeon xf86-video-amdgpu mesa" ]
  [ "$(gpu_vendor_packages nvidia)" = \
"nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver egl-wayland" ]
  [ "$(gpu_vendor_packages intel)" = "intel-media-driver" ]
  [ "$(gpu_vendor_packages vm)" = "mesa" ]
}

@test "gpu_vendor_packages: auto and unknown emit nothing" {
  [ -z "$(gpu_vendor_packages auto)" ]
  [ -z "$(gpu_vendor_packages bogus)" ]
}

# ── unit: audio ─────────────────────────────────────────────────────────────

@test "audio_packages: the PipeWire stack" {
  [ "$(audio_packages | awk 'END { print NR }')" -eq 8 ]
  audio_packages | grep -qx pipewire
  audio_packages | grep -qx libpulse
  audio_packages | grep -qx rtkit
}

# ── unit: filesystem ────────────────────────────────────────────────────────

@test "filesystem_userland_packages: per-filesystem userland, ext4 empty" {
  [ "$(filesystem_userland_packages zfs)" = "zfs-dkms zfs-utils" ]
  [ "$(filesystem_userland_packages xfs)" = "xfsprogs" ]
  [ "$(filesystem_userland_packages btrfs)" = "btrfs-progs" ]
  [ -z "$(filesystem_userland_packages ext4)" ]
  [ "$(filesystem_luks_userland_packages)" = "cryptsetup" ]
}

# ── drift guard: the shared names reach BOTH callers ─────────────────────────

@test "drift: base set — module == resolver base == in package_list_collect" {
  local config='{"users":[],"options":{"kernel":"lts"}}'
  write_config "$config"
  # query side is exactly the module
  diff <(base_packages | sort -u) <(resolved_from_source "$config" base)
  # install side contains every base name
  local out package; out="$(package_list_collect)"
  while IFS= read -r package; do grep -qx "$package" <<<"$out"; done < <(base_packages)
}

@test "drift: gpu (amd) — module == resolver == install globals" {
  local config='{"users":[],"options":{"kernel":"lts"},
    "environment":{"desktop":["kde"],"gpu":"amd"}}'
  write_config "$config"
  diff <(printf '%s\n' $(gpu_vendor_packages amd) | sort -u) <(resolved_from_source "$config" gpu)
  environment_resolve
  diff <(printf '%s\n' $(gpu_vendor_packages amd) | sort -u) \
       <(printf '%s\n' "${GPU_PACMAN_PACKAGES[@]}" | sort -u)
}

@test "drift: audio — module == resolver == install globals (desktop present)" {
  local config='{"users":[],"options":{"kernel":"lts"},
    "environment":{"desktop":["kde"],"gpu":"amd"}}'
  write_config "$config"
  diff <(audio_packages | sort -u) <(resolved_from_source "$config" audio)
  environment_resolve
  diff <(audio_packages | sort -u) \
       <(printf '%s\n' "${AUDIO_PACKAGES[@]}" | sort -u)
}

@test "drift: zfs userland — module names reach resolver and install" {
  local config='{"users":[],"options":{"kernel":"lts"},"filesystem":"zfs"}'
  write_config "$config"
  local package out
  out="$(package_list_collect)"
  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    grep -qx "$package" <<<"$out"
    resolved_from_source "$config" zfs | grep -qx "$package"
  done < <(printf '%s\n' $(filesystem_userland_packages zfs))
}
