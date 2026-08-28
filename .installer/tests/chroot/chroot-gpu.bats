#!/usr/bin/env bats
# Tests for the GPU Configuration Module in lib/chroot/gpu.sh (ADR 0053).
#
# The module hardens an AMD+NVIDIA hybrid laptop deterministically. Its pure
# cores (gating + per-artifact text generators) and thin IO seams are asserted
# here without a chroot. Source with GPU_LIB_ONLY=1 so the side-effect block
# (state load + real /etc writes + systemctl) never runs.

setup() {
  GPU_LIB_ONLY=1 source "$BATS_TEST_DIRNAME/../../lib/chroot/gpu.sh"
  ROOT="$BATS_TEST_TMPDIR/root"
}

# ── gating: only amd+nvidia hybrids harden ──────────────────────────────────

@test "gate: amd + nvidia hardens" {
  _gpu_should_harden amd nvidia
}

@test "gate: nvidia + amd (order-independent) hardens" {
  _gpu_should_harden nvidia amd
}

@test "gate: amd only does NOT harden" {
  run _gpu_should_harden amd
  [ "$status" -ne 0 ]
}

@test "gate: nvidia only does NOT harden" {
  run _gpu_should_harden nvidia
  [ "$status" -ne 0 ]
}

@test "gate: intel does NOT harden" {
  run _gpu_should_harden intel
  [ "$status" -ne 0 ]
}

@test "gate: vm does NOT harden" {
  run _gpu_should_harden vm
  [ "$status" -ne 0 ]
}

@test "gate: empty vendor list does NOT harden" {
  run _gpu_should_harden
  [ "$status" -ne 0 ]
}

# ── modprobe.d config ───────────────────────────────────────────────────────

@test "modprobe: sets nvidia_drm modeset + fbdev" {
  run _gpu_modprobe_conf
  [ "$status" -eq 0 ]
  [[ "$output" == *"options nvidia_drm modeset=1 fbdev=1"* ]]
}

@test "modprobe: preserves VRAM across suspend" {
  run _gpu_modprobe_conf
  [[ "$output" == *"NVreg_PreserveVideoMemoryAllocations=1"* ]]
}

@test "modprobe: enables fine-grained runtime power management" {
  run _gpu_modprobe_conf
  [[ "$output" == *"NVreg_DynamicPowerManagement=0x02"* ]]
}

@test "modprobe: saves preserved VRAM to disk (not tmpfs) on suspend" {
  run _gpu_modprobe_conf
  [[ "$output" == *"NVreg_TemporaryFilePath=/var/tmp"* ]]
}

@test "modprobe: blacklists nouveau" {
  run _gpu_modprobe_conf
  [[ "$output" == *"blacklist nouveau"* ]]
}

# ── amdgpu PSR (eDP panel black-screens on resume otherwise) ─────────────────

@test "amdgpu: disables Panel Self Refresh via dcdebugmask" {
  run _gpu_amdgpu_conf
  [ "$status" -eq 0 ]
  [[ "$output" == *"options amdgpu dcdebugmask=0x10"* ]]
}

# ── Early-KMS MODULES line ──────────────────────────────────────────────────

@test "modules: appends the four nvidia modules to empty MODULES" {
  run _gpu_modules_line ""
  [ "$status" -eq 0 ]
  [ "$output" = "MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)" ]
}

@test "modules: preserves existing tokens, appends nvidia in order" {
  run _gpu_modules_line "crc32c-intel"
  [ "$output" = \
    "MODULES=(crc32c-intel nvidia nvidia_modeset nvidia_uvm nvidia_drm)" ]
}

@test "modules: idempotent — no duplicate nvidia entries on re-run" {
  local once; once="$(_gpu_modules_line "")"
  local inner="${once#MODULES=(}"; inner="${inner%)}"
  run _gpu_modules_line "$inner"
  [ "$output" = "MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)" ]
}

# ── RTD3 udev rule ──────────────────────────────────────────────────────────

@test "udev: sets power/control=auto on bind for the NVIDIA VGA class" {
  run _gpu_udev_rule
  [ "$status" -eq 0 ]
  [[ "$output" == *'ACTION=="bind"'*'ATTR{vendor}=="0x10de"'*'ATTR{class}=="0x030000"'*'ATTR{power/control}="auto"'* ]]
}

@test "udev: covers the 3D-controller class variant" {
  run _gpu_udev_rule
  [[ "$output" == *'ATTR{class}=="0x030200"'* ]]
}

@test "udev: restores power/control=on on unbind" {
  run _gpu_udev_rule
  [[ "$output" == *'ACTION=="unbind"'*'ATTR{power/control}="on"'* ]]
}

# ── initramfs-regen pacman hook ─────────────────────────────────────────────

@test "hook: rebuilds initramfs via mkinitcpio -P on PostTransaction" {
  run _gpu_pacman_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"When = PostTransaction"* ]]
  [[ "$output" == *"Exec = /usr/bin/mkinitcpio -P"* ]]
}

@test "hook: triggers on nvidia and kernel package changes" {
  run _gpu_pacman_hook
  [[ "$output" == *"Target = nvidia-open-dkms"* ]]
  [[ "$output" == *"Target = linux"* ]]
  [[ "$output" == *"Target = linux-lts"* ]]
}

# ── thin IO seams write to the expected paths ───────────────────────────────

@test "io: _gpu_write_modprobe installs /etc/modprobe.d/nvidia.conf" {
  _gpu_write_modprobe "$ROOT"
  [ -f "$ROOT/etc/modprobe.d/nvidia.conf" ]
  grep -q 'modeset=1' "$ROOT/etc/modprobe.d/nvidia.conf"
}

@test "io: _gpu_write_amdgpu installs /etc/modprobe.d/amdgpu.conf" {
  _gpu_write_amdgpu "$ROOT"
  [ -f "$ROOT/etc/modprobe.d/amdgpu.conf" ]
  grep -q 'dcdebugmask=0x10' "$ROOT/etc/modprobe.d/amdgpu.conf"
}

@test "io: _gpu_write_udev_rule installs 80-nvidia-pm.rules" {
  _gpu_write_udev_rule "$ROOT"
  [ -f "$ROOT/etc/udev/rules.d/80-nvidia-pm.rules" ]
}

@test "io: _gpu_write_pacman_hook sorts after dkms (95-…)" {
  _gpu_write_pacman_hook "$ROOT"
  [ -f "$ROOT/etc/pacman.d/hooks/95-nvidia-initramfs.hook" ]
}

# ── _gpu_apply_modules edits mkinitcpio.conf in place ───────────────────────

@test "apply-modules: rewrites a default empty MODULES=() line" {
  local conf="$BATS_TEST_TMPDIR/mkinitcpio.conf"
  printf 'MODULES=()\nHOOKS=(base udev)\n' > "$conf"
  _gpu_apply_modules "$conf"
  grep -q '^MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)$' "$conf"
  # unrelated lines untouched
  grep -q '^HOOKS=(base udev)$' "$conf"
}

@test "apply-modules: idempotent across two applications" {
  local conf="$BATS_TEST_TMPDIR/mkinitcpio.conf"
  printf 'MODULES=()\n' > "$conf"
  _gpu_apply_modules "$conf"
  _gpu_apply_modules "$conf"
  [ "$(grep -c 'nvidia_drm' "$conf")" -eq 1 ]
}

# ── _gpu_harden orchestration gates on the vendor list ──────────────────────

@test "harden: hybrid writes every artifact + edits the conf" {
  local conf="$BATS_TEST_TMPDIR/mkinitcpio.conf"
  printf 'MODULES=()\n' > "$conf"
  _gpu_harden "$ROOT" "$conf" amd nvidia
  [ -f "$ROOT/etc/modprobe.d/nvidia.conf" ]
  [ -f "$ROOT/etc/modprobe.d/amdgpu.conf" ]
  [ -f "$ROOT/etc/udev/rules.d/80-nvidia-pm.rules" ]
  [ -f "$ROOT/etc/pacman.d/hooks/95-nvidia-initramfs.hook" ]
  grep -q 'nvidia_drm' "$conf"
}

@test "harden: single-vendor is a no-op (returns non-zero, writes nothing)" {
  local conf="$BATS_TEST_TMPDIR/mkinitcpio.conf"
  printf 'MODULES=()\n' > "$conf"
  run _gpu_harden "$ROOT" "$conf" amd
  [ "$status" -ne 0 ]
  [ ! -e "$ROOT/etc/modprobe.d/nvidia.conf" ]
  [ ! -e "$ROOT/etc/modprobe.d/amdgpu.conf" ]
  grep -q '^MODULES=()$' "$conf"
}
