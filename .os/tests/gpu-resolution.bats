#!/usr/bin/env bats
# Tests for resolve_gpu_packages() in lib/config.sh.
#
# Strategy: override _gpu_lspci_output() as an injectable seam so tests
# control lspci output without real hardware. Set ENVIRONMENT_GPU directly
# for non-auto tests. Assert GPU_PACMAN_PACKAGES and GPU_PARU_PACKAGES arrays.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"

  # ── common.sh stubs ────────────────────────────────────────────────────────
  jsonc_strip() { cat "$1"; }
  cfgo()    { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  cfg()     { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  error()   { echo "ERROR: $*" >&2; exit 1; }
  info()    { :; }
  section() { :; }
  warn()    { echo "WARN: $*" >&2; }
  confirm() { :; }

  # shellcheck source=../lib/environment.sh
  source "$BATS_TEST_DIRNAME/../lib/environment.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── explicit vendor strings ────────────────────────────────────────────────

@test "gpu 'amd' populates AMD package set; paru list empty" {
  ENVIRONMENT_GPU=("amd")
  resolve_gpu_packages
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" vulkan-radeon "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" xf86-video-amdgpu "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" mesa "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" libva-mesa-driver "* ]]
  [ "${#GPU_PARU_PACKAGES[@]}" -eq 0 ]
}

@test "gpu 'nvidia' populates NVIDIA open package set; paru list empty" {
  ENVIRONMENT_GPU=("nvidia")
  resolve_gpu_packages
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" nvidia-open-dkms "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" nvidia-utils "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" lib32-nvidia-utils "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" libva-nvidia-driver "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" egl-wayland "* ]]
  [ "${#GPU_PARU_PACKAGES[@]}" -eq 0 ]
}

@test "gpu ['amd','nvidia'] populates both sets and adds envycontrol to paru list" {
  ENVIRONMENT_GPU=("amd" "nvidia")
  resolve_gpu_packages
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" vulkan-radeon "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" nvidia-open-dkms "* ]]
  [[ " ${GPU_PARU_PACKAGES[*]} " == *" envycontrol "* ]]
}

# ── intel generation detection ─────────────────────────────────────────────

@test "gpu 'intel' with Broadwell+ device ID uses intel-media-driver" {
  # 0x1612 = Broadwell Iris Pro (>= 0x1600)
  _gpu_lspci_output() { echo "00:02.0 VGA [0300]: Intel Corporation [8086:1612]"; }
  ENVIRONMENT_GPU=("intel")
  resolve_gpu_packages
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" intel-media-driver "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " != *" libva-intel-driver "* ]]
}

@test "gpu 'intel' with pre-Broadwell device ID uses libva-intel-driver" {
  # 0x0a16 = Haswell (< 0x1600)
  _gpu_lspci_output() { echo "00:02.0 VGA [0300]: Intel Corporation [8086:0a16]"; }
  ENVIRONMENT_GPU=("intel")
  resolve_gpu_packages
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" libva-intel-driver "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " != *" intel-media-driver "* ]]
}

# ── auto detection ─────────────────────────────────────────────────────────

@test "auto with AMD lspci resolves to AMD packages" {
  _gpu_lspci_output() { echo "00:00.0 VGA [0300]: Advanced Micro Devices [AMD/ATI] Navi 21 [1002:73bf]"; }
  ENVIRONMENT_GPU=("auto")
  resolve_gpu_packages
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" vulkan-radeon "* ]]
}

@test "auto with hybrid AMD+NVIDIA lspci resolves both sets and adds envycontrol" {
  _gpu_lspci_output() {
    echo "00:00.0 VGA [0300]: Advanced Micro Devices [AMD/ATI] Renoir [1002:1636]"
    echo "01:00.0 VGA [0300]: NVIDIA Corporation GA107M [GeForce RTX 3050] [10de:25a2]"
  }
  ENVIRONMENT_GPU=("auto")
  resolve_gpu_packages
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" vulkan-radeon "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" nvidia-open-dkms "* ]]
  [[ " ${GPU_PARU_PACKAGES[*]} " == *" envycontrol "* ]]
}

@test "auto with VMware GPU resolves to mesa only; does not abort" {
  _gpu_lspci_output() { echo "00:0f.0 VGA [0300]: VMware SVGA II Adapter [15ad:0405]"; }
  ENVIRONMENT_GPU=("auto")
  resolve_gpu_packages
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" mesa "* ]]
  [ "${#GPU_PACMAN_PACKAGES[@]}" -eq 1 ]
  [ "${#GPU_PARU_PACKAGES[@]}" -eq 0 ]
}

@test "auto with virtio-gpu resolves to mesa only; does not abort" {
  _gpu_lspci_output() { echo "00:02.0 VGA [0300]: Red Hat, Inc. Virtio GPU [1af4:1050]"; }
  ENVIRONMENT_GPU=("auto")
  resolve_gpu_packages
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" mesa "* ]]
  [ "${#GPU_PACMAN_PACKAGES[@]}" -eq 1 ]
}
