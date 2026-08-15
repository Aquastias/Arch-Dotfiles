#!/usr/bin/env bash
# =============================================================================
# lib/chroot/bootloader-common.sh — shared ESP-mirroring adapter preamble
# =============================================================================
# Sourced by every ESP-mirroring Bootloader Adapter (systemd-boot, efistub,
# limine, refind) AFTER chroot-common, with STATE set. grub does NOT use it
# (it reads /boot natively and needs no ESP mirror). Sources the kernel /
# microcode / zswap / entry-renderer libs and computes the values every
# ESP-mirroring adapter needs, plus the ESP staging + ESP Kernel Sync hook
# installation they all repeat (ADR 0038/0077/0078). Requires _LIB_DIR + STATE
# set by the caller.
# =============================================================================

# _bl_src <staged-name> <dev-relpath> — source a lib whether staged flat into
# lib-chroot or read from the dev tree.
_bl_src() {
  local s="$_LIB_DIR/$1"
  [[ -f "$s" ]] || s="$_LIB_DIR/$2"
  # shellcheck disable=SC1090
  source "$s"
}
_bl_src install-state.sh  ../install-state.sh
install_state_load "$STATE"
_bl_src kernel.sh         ../packages/kernel.sh
_bl_src microcode.sh      ../packages/microcode.sh
_bl_src zswap.sh          ../boot/zswap.sh
_bl_src loader-entries.sh ../boot/loader-entries.sh

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
DEFAULT_OPTS="${ROOT_CMDLINE} rw${ZSWAP_CMDLINE:+ ${ZSWAP_CMDLINE}}"
QUIET_CMDLINE=""
[[ -n "${ENVIRONMENT_DESKTOP:-}" ]] \
  && QUIET_CMDLINE="quiet loglevel=3 systemd.show_status=false"

# blcommon_stage_kernel <kbase> — copy vmlinuz + default initramfs onto the ESP,
# generate + copy the fallback initramfs when the preset did not. Prints the
# fallback image name when it exists (so the caller renders a fallback entry),
# nothing otherwise.
blcommon_stage_kernel() {
  local kbase="$1"
  local initramfs="initramfs-${kbase}.img"
  local initramfs_fb="initramfs-${kbase}-fallback.img"
  cp "/boot/vmlinuz-${kbase}" "$ESP/"
  cp "/boot/${initramfs}"     "$ESP/"
  if [[ ! -f "/boot/${initramfs_fb}" ]]; then
    mkinitcpio -p "$kbase" -S autodetect 2>/dev/null \
      || mkinitcpio -g "/boot/${initramfs_fb}" 2>/dev/null || true
  fi
  if [[ -f "/boot/${initramfs_fb}" ]]; then
    cp "/boot/${initramfs_fb}" "$ESP/"
    printf '%s\n' "$initramfs_fb"
  fi
}

# blcommon_esp_disk_part [<esp-mount>] — print "<disk> <part>" for the ESP's
# backing device, for efibootmgr --disk/--part. nvme/mmc use a `p<N>` partition
# suffix, sata does not. Shared so no adapter hardcodes the partition number.
blcommon_esp_disk_part() {
  local mnt="${1:-$ESP}" dev disk part
  dev="$(findmnt -n -o SOURCE "$mnt")"
  if [[ "$dev" =~ nvme|mmcblk ]]; then
    disk="${dev%p[0-9]*}"; part="${dev##*p}"
  else
    disk="${dev%[0-9]*}"; part="${dev##*[a-z]}"
  fi
  printf '%s %s\n' "$disk" "$part"
}

# blcommon_stage_microcode — copy the present vendor microcode image(s) to ESP.
blcommon_stage_microcode() {
  [[ -f /boot/intel-ucode.img ]] && cp /boot/intel-ucode.img "$ESP/" || true
  [[ -f /boot/amd-ucode.img   ]] && cp /boot/amd-ucode.img   "$ESP/" || true
}

# blcommon_efistub_register <disk> <part> <label_suffix> — register one
# efibootmgr entry per selected kernel (default + fallback), each pointing at
# the ESP-mirrored kernel with initrd + cmdline load-options (efistub has no
# loader binary). The Primary Kernel is registered LAST so its default entry
# lands first in BootOrder. Shared by the efistub adapter (primary ESP) and the
# secondary-ESP loop, so every disk carries identical entries (ADR 0078).
blcommon_efistub_register() {
  local disk="$1" part="$2" suffix="$3" kb fb opts t
  local -a order=()
  for t in "${KERNELS[@]}"; do
    kb="$(kernel_pkg "$t")"
    [[ "$kb" == "$PRIMARY_KBASE" ]] || order+=("$kb")
  done
  order+=("$PRIMARY_KBASE")
  for kb in "${order[@]}"; do
    fb="initramfs-${kb}-fallback.img"
    if [[ -f "$ESP/$fb" ]]; then
      opts="$(efistub_load_options "$fb" "$MICROCODE_IMGS" "$DEFAULT_OPTS")"
      efibootmgr --create --disk "$disk" --part "$part" \
        --label "Arch (${kb} fallback${suffix:+ $suffix})" \
        --loader "\\vmlinuz-${kb}" --unicode "$opts" || true
    fi
    opts="$(efistub_load_options "initramfs-${kb}.img" "$MICROCODE_IMGS" \
      "${DEFAULT_OPTS}${QUIET_CMDLINE:+ ${QUIET_CMDLINE}}")"
    efibootmgr --create --disk "$disk" --part "$part" \
      --label "Arch (${kb}${suffix:+ $suffix})" \
      --loader "\\vmlinuz-${kb}" --unicode "$opts" || true
  done
}

# blcommon_install_esp_sync_hooks — install the ESP Kernel Sync helper + the
# pacman preflight/sync hooks every ESP-mirroring loader needs (ADR 0038).
blcommon_install_esp_sync_hooks() {
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
