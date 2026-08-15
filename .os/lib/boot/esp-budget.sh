#!/usr/bin/env bash
# =============================================================================
# lib/boot/esp-budget.sh — pre-install ESP budget model (ADR 0078)
# =============================================================================
# Pure arithmetic that sizes the FAT ESP from the Kernel Selection so a
# many-kernel install can never overflow it mid-upgrade (the brick ADR 0038 was
# written to prevent, re-triggered by multi-kernel). It is an ESTIMATE — the ESP
# is partitioned before any initramfs is built, so it uses a per-kernel budget,
# not real file sizes; ADR 0038's runtime PreTransaction preflight stays the
# truth-time backstop. Only ESP-mirroring loaders count kernels; grub reads
# /boot natively and takes a fixed small ESP.
#
# Measured budget (raw layout, ADR 0078): vmlinuz ~16M, default initramfs ~54M,
# fallback initramfs ~205M, zfs module ~+30M/kernel. Pure: no disk or state.
# =============================================================================

_ESP_BUDGET_BASE_MIB=180        # loaders + loader dir + overhead
_ESP_BUDGET_VMLINUZ_MIB=16
_ESP_BUDGET_DEFAULT_MIB=54
_ESP_BUDGET_FALLBACK_MIB=205
_ESP_BUDGET_ZFS_MIB=30          # zfs module surcharge per kernel (zfs root)
_ESP_BUDGET_TRANSIENT_MIB=205   # one fallback temp-then-rename during a sync
_ESP_BUDGET_GRUB_MIB=512        # grub's tiny fixed ESP (kernels stay on /boot)
_ESP_BUDGET_FLOOR_MIB=2048      # ADR 0038's 2G default — auto never goes below

# esp_budget_need_mib <kernel_count> <fs> <loader> — estimated ESP need in MiB.
esp_budget_need_mib() {
  local n="$1" fs="$2" loader="$3"
  if [[ "$loader" == grub ]]; then
    printf '%s\n' "$_ESP_BUDGET_GRUB_MIB"; return 0
  fi
  local per=$(( _ESP_BUDGET_VMLINUZ_MIB + _ESP_BUDGET_DEFAULT_MIB \
                + _ESP_BUDGET_FALLBACK_MIB ))
  [[ "$fs" == zfs ]] && per=$(( per + _ESP_BUDGET_ZFS_MIB ))
  # base + every selected kernel + transient sync headroom + one-kernel slack.
  printf '%s\n' "$(( _ESP_BUDGET_BASE_MIB + n * per \
                     + _ESP_BUDGET_TRANSIENT_MIB + per ))"
}

# _esp_mib_to_size <mib> — a whole-GiB value prints as NG, otherwise NM.
_esp_mib_to_size() {
  local m="$1"
  if (( m % 1024 == 0 )); then printf '%sG\n' "$(( m / 1024 ))"
  else printf '%sM\n' "$m"; fi
}

# esp_budget_auto_size <kernel_count> <fs> <loader> — the resolved esp_size
# string. grub → its fixed small ESP; ESP-mirroring loaders → the need rounded
# up to 256 MiB, never below the 2G floor (upward-only).
esp_budget_auto_size() {
  local n="$1" fs="$2" loader="$3" need mib
  need="$(esp_budget_need_mib "$n" "$fs" "$loader")"
  if [[ "$loader" == grub ]]; then _esp_mib_to_size "$need"; return 0; fi
  mib=$(( (need + 255) / 256 * 256 ))
  (( mib < _ESP_BUDGET_FLOOR_MIB )) && mib=$_ESP_BUDGET_FLOOR_MIB
  _esp_mib_to_size "$mib"
}

# esp_budget_fits_mib <have_mib> <kernel_count> <fs> <loader> — rc 0 when an ESP
# of <have_mib> holds the estimated need. grub is always exempt.
esp_budget_fits_mib() {
  local have="$1" n="$2" fs="$3" loader="$4"
  [[ "$loader" == grub ]] && return 0
  local need; need="$(esp_budget_need_mib "$n" "$fs" "$loader")"
  (( have >= need ))
}

# esp_budget_size_mib <size> — parse an esp_size string ("2G"/"512M"/bare) to
# MiB. Deliberately mirrors layout core's parse_size_to_mib so this budget lib
# stays standalone (layout/core.sh sources THIS; a back-dependency would loop).
esp_budget_size_mib() {
  local s="${1^^}" num unit
  num="${s//[^0-9]/}"; unit="${s//[0-9]/}"
  case "$unit" in
  G | GIB) printf '%s\n' "$(( num * 1024 ))" ;;
  *)       printf '%s\n' "${num:-0}" ;;   # M / MiB / bare → MiB
  esac
}

# esp_budget_fits_size <size> <kernel_count> <fs> <loader> — like
# esp_budget_fits_mib but takes an esp_size string. `auto` always fits (it is
# resolved upward by construction), so only a numeric pin can fail.
esp_budget_fits_size() {
  [[ "$1" == auto ]] && return 0
  esp_budget_fits_mib "$(esp_budget_size_mib "$1")" "$2" "$3" "$4"
}
