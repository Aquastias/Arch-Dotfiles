#!/usr/bin/env bash
# =============================================================================
# vm/lib/esp-resilience-verify.sh — booted-system boot-resilience verifier
# =============================================================================
# Test-only (ADR 0038). Composes the REAL installed hardening modules (the ESP
# Kernel Sync + the Stray Kernel detector) and asserts their guards actually
# fire on the brick precondition: a critical copy that cannot complete must fail
# loudly while preserving the prior image, and a planted Stray Kernel must be
# detected. Returns 0 only when every guard behaves — the first-boot oneshot
# emits the sentinel only then, so the host boot-verify times out (test fails)
# if any guard regresses.
#
# Overridable seams default to the installed locations; tests point them at the
# repo's lib/boot modules.
# =============================================================================

: "${ESP_SYNC_SH:=/usr/local/lib/archzfs/esp-kernel-sync.sh}"
: "${STRAY_SH:=/usr/local/lib/archzfs/stray-kernel.sh}"

esp_resilience_verify() {
  [[ -f "$ESP_SYNC_SH" && -f "$STRAY_SH" ]] || {
    echo "FAIL: hardening modules not installed" >&2
    return 1
  }
  # Load the real shared logic lib-only (define functions, skip the runtime).
  # shellcheck disable=SC1090
  ESP_KERNEL_SYNC_LIB_ONLY=1 source "$ESP_SYNC_SH" || return 1
  # shellcheck disable=SC1090
  STRAY_KERNEL_LIB_ONLY=1 source "$STRAY_SH" || return 1

  local work esp boot mods
  work="$(mktemp -d)"
  esp="$work/esp"
  boot="$work/boot"
  mods="$work/modules"
  mkdir -p "$esp/loader/entries" "$boot" "$mods"
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" RETURN

  # Guard 1 — a critical copy that cannot complete must fail and leave the prior
  # image intact (the full-ESP path; a missing source stands in for ENOSPC).
  printf 'OLD' >"$esp/initramfs-linux-lts.img"
  if esp_sync_install_critical "$boot/missing.img" \
    "$esp/initramfs-linux-lts.img" 2>/dev/null; then
    echo "FAIL: install_critical did not fail on an impossible copy" >&2
    return 1
  fi
  [[ "$(cat "$esp/initramfs-linux-lts.img")" == OLD ]] || {
    echo "FAIL: prior boot image was not preserved" >&2
    return 1
  }

  # Guard 2 — a planted Stray Kernel must be detected.
  mkdir -p "$mods/6.18-lts" "$mods/7.0-rolling"
  echo linux-lts >"$mods/6.18-lts/pkgbase"
  echo linux >"$mods/7.0-rolling/pkgbase"
  [[ "$(stray_kernels "$mods" linux-lts)" == *linux* ]] || {
    echo "FAIL: Stray Kernel was not detected" >&2
    return 1
  }

  return 0
}
