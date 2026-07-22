#!/usr/bin/env bats
# Tests for _resolve_env_gpu() in lib/config/lifecycle.sh.
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

  # shellcheck source=../../lib/config/environment.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/environment.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── explicit vendor strings ────────────────────────────────────────────────

@test "gpu 'amd' populates AMD package set; paru list empty" {
  ENVIRONMENT_GPU=("amd")
  _resolve_env_gpu
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" vulkan-radeon "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" xf86-video-amdgpu "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" mesa "* ]]
  # libva-mesa-driver is no longer a standalone package — mesa provides it.
  [[ " ${GPU_PACMAN_PACKAGES[*]} " != *" libva-mesa-driver "* ]]
  [ "${#GPU_PARU_PACKAGES[@]}" -eq 0 ]
}

@test "gpu 'nvidia' populates NVIDIA open package set; paru list empty" {
  ENVIRONMENT_GPU=("nvidia")
  _resolve_env_gpu
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" nvidia-open-dkms "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" nvidia-utils "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" lib32-nvidia-utils "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" libva-nvidia-driver "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" egl-wayland "* ]]
  [ "${#GPU_PARU_PACKAGES[@]}" -eq 0 ]
}

@test "gpu ['amd','nvidia'] populates both sets and adds envycontrol" {
  ENVIRONMENT_GPU=("amd" "nvidia")
  _resolve_env_gpu
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" vulkan-radeon "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" nvidia-open-dkms "* ]]
  [[ " ${GPU_PARU_PACKAGES[*]} " == *" envycontrol "* ]]
}

# ── intel generation detection ─────────────────────────────────────────────

@test "gpu 'intel' with Broadwell+ device ID uses intel-media-driver" {
  # 0x1612 = Broadwell Iris Pro (>= 0x1600)
  _gpu_lspci_output() {
    echo "00:02.0 VGA [0300]: Intel Corporation [8086:1612]"
  }
  ENVIRONMENT_GPU=("intel")
  _resolve_env_gpu
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" intel-media-driver "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " != *" libva-intel-driver "* ]]
}

@test "gpu 'intel' with pre-Broadwell device ID uses libva-intel-driver" {
  # 0x0a16 = Haswell (< 0x1600)
  _gpu_lspci_output() {
    echo "00:02.0 VGA [0300]: Intel Corporation [8086:0a16]"
  }
  ENVIRONMENT_GPU=("intel")
  _resolve_env_gpu
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" libva-intel-driver "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " != *" intel-media-driver "* ]]
}

# ── auto detection ─────────────────────────────────────────────────────────

@test "auto with AMD lspci resolves to AMD packages" {
  _gpu_lspci_output() {
    echo "00:00.0 VGA [0300]: Advanced Micro Devices" \
         "[AMD/ATI] Navi 21 [1002:73bf]"
  }
  ENVIRONMENT_GPU=("auto")
  _resolve_env_gpu
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" vulkan-radeon "* ]]
}

@test "auto with hybrid AMD+NVIDIA lspci resolves both + envycontrol" {
  _gpu_lspci_output() {
    echo "00:00.0 VGA [0300]: Advanced Micro Devices" \
         "[AMD/ATI] Renoir [1002:1636]"
    echo "01:00.0 VGA [0300]: NVIDIA Corporation GA107M" \
         "[GeForce RTX 3050] [10de:25a2]"
  }
  ENVIRONMENT_GPU=("auto")
  _resolve_env_gpu
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" vulkan-radeon "* ]]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" nvidia-open-dkms "* ]]
  [[ " ${GPU_PARU_PACKAGES[*]} " == *" envycontrol "* ]]
}

@test "auto with VMware GPU resolves to mesa only; does not abort" {
  _gpu_lspci_output() {
    echo "00:0f.0 VGA [0300]: VMware SVGA II Adapter [15ad:0405]"
  }
  ENVIRONMENT_GPU=("auto")
  _resolve_env_gpu
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" mesa "* ]]
  [ "${#GPU_PACMAN_PACKAGES[@]}" -eq 1 ]
  [ "${#GPU_PARU_PACKAGES[@]}" -eq 0 ]
}

@test "auto with virtio-gpu resolves to mesa only; does not abort" {
  _gpu_lspci_output() {
    echo "00:02.0 VGA [0300]: Red Hat, Inc. Virtio GPU [1af4:1050]"
  }
  ENVIRONMENT_GPU=("auto")
  _resolve_env_gpu
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" mesa "* ]]
  [ "${#GPU_PACMAN_PACKAGES[@]}" -eq 1 ]
}

# ── Hybrid GPU session env (Bug: Hyprland black screen on nvidia+iGPU) ───────
# gpu_hybrid_aq_drm_devices emits AQ_DRM_DEVICES with the integrated GPU first so
# a Wayland compositor scans out on the panel's GPU. _gpu_lspci_output_d is the
# injectable seam (domain-qualified lspci).
_fake_lspci_d_hybrid() {
  echo '0000:34:00.0 VGA compatible controller [0300]: AMD Rembrandt [1002:1681] (rev cc)'
  echo '0000:01:00.0 VGA compatible controller [0300]: NVIDIA GA106M [GeForce RTX 3060 Mobile] [10de:2560] (rev a1)'
  echo '0000:01:00.1 Audio device [0403]: NVIDIA GA106 HD Audio [10de:228e] (rev a1)'
}

@test "hybrid: AQ_DRM_DEVICES lists integrated GPU first, nvidia second" {
  ENVIRONMENT_GPU=("amd" "nvidia")
  _gpu_lspci_output_d() { _fake_lspci_d_hybrid; }
  run gpu_hybrid_aq_drm_devices
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/dri/by-path/pci-0000:34:00.0-card:/dev/dri/by-path/pci-0000:01:00.0-card" ]
}

@test "hybrid: single-vendor nvidia GPU emits nothing" {
  ENVIRONMENT_GPU=("nvidia")
  _gpu_lspci_output_d() { echo '0000:01:00.0 VGA compatible controller [0300]: NVIDIA [10de:2560]'; }
  run gpu_hybrid_aq_drm_devices
  [ -z "$output" ]
}

@test "hybrid: amd-only (no nvidia) emits nothing" {
  ENVIRONMENT_GPU=("amd")
  _gpu_lspci_output_d() { _fake_lspci_d_hybrid; }
  run gpu_hybrid_aq_drm_devices
  [ -z "$output" ]
}

@test "hybrid: intel+nvidia uses the intel iGPU first" {
  ENVIRONMENT_GPU=("intel" "nvidia")
  _gpu_lspci_output_d() {
    echo '0000:00:02.0 VGA compatible controller [0300]: Intel [8086:9a49]'
    echo '0000:01:00.0 3D controller [0302]: NVIDIA [10de:2560]'
  }
  run gpu_hybrid_aq_drm_devices
  [ "$output" = "/dev/dri/by-path/pci-0000:00:02.0-card:/dev/dri/by-path/pci-0000:01:00.0-card" ]
}

@test "gpu_write_session_env writes AQ_DRM_DEVICES under <root>/etc/environment" {
  ENVIRONMENT_GPU=("amd" "nvidia")
  _gpu_lspci_output_d() { _fake_lspci_d_hybrid; }
  local root="$TEST_DIR/mnt"; mkdir -p "$root/etc"
  gpu_write_session_env "$root"
  grep -qF 'AQ_DRM_DEVICES=/dev/dri/by-path/pci-0000:34:00.0-card:/dev/dri/by-path/pci-0000:01:00.0-card' "$root/etc/environment"
}

@test "gpu_write_session_env does NOT set global GLX/VA vars (greeter regression)" {
  ENVIRONMENT_GPU=("amd" "nvidia")
  _gpu_lspci_output_d() { _fake_lspci_d_hybrid; }
  local root="$TEST_DIR/mnt"; mkdir -p "$root/etc"
  gpu_write_session_env "$root"
  # forcing nvidia GLX/VA globally blanks the SDDM greeter on the iGPU panel
  ! grep -q 'LIBVA_DRIVER_NAME' "$root/etc/environment"
  ! grep -q '__GLX_VENDOR_LIBRARY_NAME' "$root/etc/environment"
  ! grep -q 'NVD_BACKEND' "$root/etc/environment"
}

@test "gpu_write_session_env is a no-op for non-hybrid GPUs" {
  ENVIRONMENT_GPU=("amd")
  _gpu_lspci_output_d() { _fake_lspci_d_hybrid; }
  local root="$TEST_DIR/mnt"; mkdir -p "$root/etc"
  gpu_write_session_env "$root"
  [ ! -f "$root/etc/environment" ]
}

@test "gpu_write_session_env is idempotent (single AQ_DRM_DEVICES line)" {
  ENVIRONMENT_GPU=("amd" "nvidia")
  _gpu_lspci_output_d() { _fake_lspci_d_hybrid; }
  local root="$TEST_DIR/mnt"; mkdir -p "$root/etc"
  gpu_write_session_env "$root"
  gpu_write_session_env "$root"
  [ "$(grep -c '^AQ_DRM_DEVICES=' "$root/etc/environment")" -eq 1 ]
}

@test "gpu_write_session_env preserves pre-existing /etc/environment lines" {
  ENVIRONMENT_GPU=("amd" "nvidia")
  _gpu_lspci_output_d() { _fake_lspci_d_hybrid; }
  local root="$TEST_DIR/mnt"; mkdir -p "$root/etc"
  echo 'EXISTING=1' > "$root/etc/environment"
  gpu_write_session_env "$root"
  grep -qxF 'EXISTING=1' "$root/etc/environment"
}
