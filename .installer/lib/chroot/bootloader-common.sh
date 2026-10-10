#!/usr/bin/env bash
# =============================================================================
# lib/chroot/bootloader-common.sh — shared ESP-mirroring adapter preamble
# =============================================================================
# Sourced by every Bootloader Adapter that boots kernels staged on the ESP
# (systemd-boot, efistub, limine, refind, grub) AFTER chroot-common, with
# STATE set. Sources the kernel / microcode / zswap / entry-renderer libs and
# computes the values every ESP-mirroring adapter needs, plus the ESP staging
# + ESP Kernel Sync hook installation they all repeat (ADR 0038/0077/0078).
# Requires _LIB_DIR + STATE set by the caller.
# =============================================================================

# _bootloader_common_source <staged-name> <dev-relpath> — source a lib whether
# staged flat into lib-chroot or read from the dev tree.
_bootloader_common_source() {
  local source_path="$_LIB_DIR/$1"
  [[ -f "$source_path" ]] || source_path="$_LIB_DIR/$2"
  # shellcheck disable=SC1090
  source "$source_path"
}
_bootloader_common_source install-state.sh  ../install-state.sh
install_state_load "$STATE"
_bootloader_common_source kernel.sh         ../packages/kernel.sh
_bootloader_common_source microcode.sh      ../packages/microcode.sh
_bootloader_common_source zswap.sh          ../boot/zswap.sh
_bootloader_common_source lsm.sh            ../boot/lsm.sh
_bootloader_common_source vm-video.sh       ../boot/vm-video.sh
_bootloader_common_source esp-stage.sh      ../boot/esp-stage.sh
_bootloader_common_source loader-entries.sh ../boot/loader-entries.sh

ESP="/boot/efi"

# Primary Kernel (KERNELS[0] == KERNEL) drives every loader's default entry.
PRIMARY_KBASE="$(kernel_pkg "$KERNEL")"

# Microcode: the systemd-boot-style "initrd  /<img>" block (for file-based
# loaders) and the bare image list (for efistub load-options). Rendered from the
# *-ucode.img actually present so an entry never references a missing initrd.
# MICROCODE_INITRDS is consumed by sourcing adapters (systemd-boot/limine).
# shellcheck disable=SC2034
MICROCODE_INITRDS="$(microcode_present_initrds /boot)"
MICROCODE_IMGS=""
[[ -f /boot/intel-ucode.img ]] && MICROCODE_IMGS+="intel-ucode.img "
[[ -f /boot/amd-ucode.img   ]] && MICROCODE_IMGS+="amd-ucode.img "
MICROCODE_IMGS="${MICROCODE_IMGS% }"

# root= cmdline + rw + optional zswap fragment; desktop installs boot quietly so
# the greeter VT stays clean (fallback entries stay verbose).
ZSWAP_CMDLINE="$(zswap_cmdline_params "$(cat "$STATE")")"
# AppArmor's LSM order (installer-owned, so every loader carries it).
LSM_CMDLINE="$(lsm_cmdline_params "$(cat "$STATE")")"
# VM Full-HD floor (ADR 0119): pin a video= mode when installing inside a VM so
# the guest's virtual panel does not come up sub-FHD. Bare metal emits nothing —
# resolution stays autodetected (ADR 0110). systemd-detect-virt exits non-zero
# and prints nothing on bare metal; `|| echo none` normalises that to the empty
# fragment. Applied to every entry (default + fallback) so recovery is FHD too.
# INSTALL_EXTRA_CMDLINE is test-only: the VM harness sets console=ttyS0 so the
# Console Answerer sees every loader's unlock prompt (ADR 0152).
VM_VIDEO_CMDLINE="$(vm_video_cmdline_params \
  "$(systemd-detect-virt 2>/dev/null || echo none)")"
DEFAULT_OPTS="${ROOT_CMDLINE} rw${ZSWAP_CMDLINE:+ ${ZSWAP_CMDLINE}}\
${LSM_CMDLINE:+ ${LSM_CMDLINE}}\
${VM_VIDEO_CMDLINE:+ ${VM_VIDEO_CMDLINE}}\
${INSTALL_EXTRA_CMDLINE:+ ${INSTALL_EXTRA_CMDLINE}}"
QUIET_CMDLINE=""
[[ -n "${ENVIRONMENT_DESKTOP:-}" ]] \
  && QUIET_CMDLINE="quiet loglevel=3 systemd.show_status=false"

# bootloader_common_stage_kernel <kbase> — esp_stage_kernel onto this ESP:
# prints only the fallback image name (or nothing) for the caller's entry.
bootloader_common_stage_kernel() { esp_stage_kernel "$1" "$ESP"; }

# bootloader_common_esp_disk_partition [<esp-mount>] — print "<disk> <part>" for
# the ESP's backing device, for efibootmgr --disk/--part. nvme/mmc use a `p<N>`
# partition suffix, sata does not. Shared so no adapter hardcodes the partition
# number.
bootloader_common_esp_disk_partition() {
  local mountpoint="${1:-$ESP}" dev disk part
  dev="$(findmnt -n -o SOURCE "$mountpoint")"
  if [[ "$dev" =~ nvme|mmcblk ]]; then
    disk="${dev%p[0-9]*}"; part="${dev##*p}"
  else
    disk="${dev%[0-9]*}"; part="${dev##*[a-z]}"
  fi
  printf '%s %s\n' "$disk" "$part"
}

# bootloader_common_stage_microcode — copy the present vendor microcode image(s)
# to ESP.
bootloader_common_stage_microcode() {
  [[ -f /boot/intel-ucode.img ]] && cp /boot/intel-ucode.img "$ESP/" || true
  [[ -f /boot/amd-ucode.img   ]] && cp /boot/amd-ucode.img   "$ESP/" || true
}

# bootloader_common_efistub_register <disk> <part> <label_suffix> — register one
# efibootmgr entry per selected kernel (default + fallback), each pointing at
# the ESP-mirrored kernel with initrd + cmdline load-options (efistub has no
# loader binary). The Primary Kernel is registered LAST so its default entry
# lands first in BootOrder. Shared by the efistub adapter (primary ESP) and the
# secondary-ESP loop, so every disk carries identical entries (ADR 0078).
bootloader_common_efistub_register() {
  local disk="$1" part="$2" suffix="$3" kb fallback_image options title
  local -a order=()
  for title in "${KERNELS[@]}"; do
    kb="$(kernel_pkg "$title")"
    [[ "$kb" == "$PRIMARY_KBASE" ]] || order+=("$kb")
  done
  order+=("$PRIMARY_KBASE")
  for kb in "${order[@]}"; do
    fallback_image="initramfs-${kb}-fallback.img"
    if [[ -f "$ESP/$fallback_image" ]]; then
      options="$(loader_entries_efistub_options "$fallback_image" \
        "$MICROCODE_IMGS" "$DEFAULT_OPTS")"
      efibootmgr --create --disk "$disk" --part "$part" \
        --label "Arch (${kb} fallback${suffix:+ $suffix})" \
        --loader "\\vmlinuz-${kb}" --unicode "$options" || true
    fi
    options="$(loader_entries_efistub_options "initramfs-${kb}.img" \
      "$MICROCODE_IMGS" \
      "${DEFAULT_OPTS}${QUIET_CMDLINE:+ ${QUIET_CMDLINE}}")"
    efibootmgr --create --disk "$disk" --part "$part" \
      --label "Arch (${kb}${suffix:+ $suffix})" \
      --loader "\\vmlinuz-${kb}" --unicode "$options" || true
  done
}

# bootloader_common_install_esp_sync_hooks — install the ESP Kernel Sync helper
# + the pacman preflight/sync hooks every ESP-mirroring loader needs (ADR 0038).
bootloader_common_install_esp_sync_hooks() {
  mkdir -p /etc/pacman.d/hooks
  install -Dm755 "$_LIB_DIR/esp-kernel-sync.sh" \
    /usr/local/lib/archzfs/esp-kernel-sync.sh
  cat > /etc/pacman.d/hooks/93-esp-kernel-sync-preflight.hook << 'HOOK'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = Checking ESP free space for new boot images...
When = PreTransaction
Exec = /usr/local/lib/archzfs/esp-kernel-sync.sh preflight
AbortOnFail
HOOK
  cat > /etc/pacman.d/hooks/94-esp-kernel-sync.hook << 'HOOK'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = Syncing kernel and initramfs to ESP...
When = PostTransaction
Exec = /usr/local/lib/archzfs/esp-kernel-sync.sh
HOOK
}
