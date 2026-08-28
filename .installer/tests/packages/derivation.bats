#!/usr/bin/env bats
# Tests for the shared pure package maps (base / gpu / audio / filesystem) and
# the DRIFT GUARD that locks them: the same names must reach both callers — the
# install path (collect_packages / resolve_environment) and the Package Resolver
# (pkgres_resolve). A future re-hardcode in either caller fails here, not in a
# VM. gpu is pinned to an explicit vendor so the guard stays deterministic and
# headless (no lspci).

setup() {
  export OS_DIR="$BATS_TEST_DIRNAME/../.."
  TEST_DIR="$(mktemp -d)"
  CONFIG_FILE="$TEST_DIR/install.json"
  export CONFIG_FILE
  source "$OS_DIR/lib/common.sh"
  source "$OS_DIR/lib/config/accessors.sh"
  source "$OS_DIR/lib/packages/base.sh"
  source "$OS_DIR/lib/packages/gpu.sh"
  source "$OS_DIR/lib/packages/audio.sh"
  source "$OS_DIR/lib/packages/filesystem.sh"
  source "$OS_DIR/lib/packages/list.sh"
  source "$OS_DIR/lib/config/environment.sh"
  source "$OS_DIR/lib/packages/resolver.sh"
  # Keep gpu resolution deterministic even if a test uses intel/auto.
  _gpu_lspci_output() { printf ''; }
}

teardown() { rm -rf "$TEST_DIR"; }

write_config() { printf '%s\n' "$1" >"$CONFIG_FILE"; }
res_src() { pkgres_resolve "$1" | awk -F'\t' -v s="$2" '$1==s{print $3}' | sort -u; }

# ── unit: base ──────────────────────────────────────────────────────────────

@test "base_packages: the unconditional 18-package set" {
  run base_packages
  [ "$status" -eq 0 ]
  [ "$(base_packages | sort -u | wc -l)" -eq 18 ]
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
  [ "$(audio_packages | wc -l)" -eq 7 ]
  audio_packages | grep -qx pipewire
  audio_packages | grep -qx libpulse
}

# ── unit: filesystem ────────────────────────────────────────────────────────

@test "fs_userland_packages: per-filesystem userland, ext4 empty" {
  [ "$(fs_userland_packages zfs)" = "zfs-dkms zfs-utils" ]
  [ "$(fs_userland_packages xfs)" = "xfsprogs" ]
  [ "$(fs_userland_packages btrfs)" = "btrfs-progs" ]
  [ -z "$(fs_userland_packages ext4)" ]
  [ "$(luks_userland_packages)" = "cryptsetup" ]
}

# ── drift guard: the shared names reach BOTH callers ─────────────────────────

@test "drift: base set — module == resolver base == in collect_packages" {
  local cfg='{"users":[],"options":{"kernel":"lts"}}'
  write_config "$cfg"
  # query side is exactly the module
  diff <(base_packages | sort -u) <(res_src "$cfg" base)
  # install side contains every base name
  local out p; out="$(collect_packages)"
  while IFS= read -r p; do grep -qx "$p" <<<"$out"; done < <(base_packages)
}

@test "drift: gpu (amd) — module == resolver == install globals" {
  local cfg='{"users":[],"options":{"kernel":"lts"},
    "environment":{"desktop":["kde"],"gpu":"amd"}}'
  write_config "$cfg"
  diff <(gpu_vendor_packages amd | tr ' ' '\n' | sort -u) <(res_src "$cfg" gpu)
  resolve_environment
  diff <(gpu_vendor_packages amd | tr ' ' '\n' | sort -u) \
       <(printf '%s\n' "${GPU_PACMAN_PACKAGES[@]}" | sort -u)
}

@test "drift: audio — module == resolver == install globals (desktop present)" {
  local cfg='{"users":[],"options":{"kernel":"lts"},
    "environment":{"desktop":["kde"],"gpu":"amd"}}'
  write_config "$cfg"
  diff <(audio_packages | sort -u) <(res_src "$cfg" audio)
  resolve_environment
  diff <(audio_packages | sort -u) \
       <(printf '%s\n' "${AUDIO_PACKAGES[@]}" | sort -u)
}

@test "drift: zfs userland — module names reach resolver and install" {
  local cfg='{"users":[],"options":{"kernel":"lts"},"filesystem":"zfs"}'
  write_config "$cfg"
  local p out
  out="$(collect_packages)"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    grep -qx "$p" <<<"$out"
    res_src "$cfg" zfs | grep -qx "$p"
  done < <(fs_userland_packages zfs | tr ' ' '\n')
}
