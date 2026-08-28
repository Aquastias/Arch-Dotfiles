#!/usr/bin/env bats
# Tests for vm/lib/esp-resilience-verify.sh — the boot-resilience first-boot
# check. Points the module seams at the repo's lib/boot modules so the verifier
# composes the real hardening logic (ADR 0038).

setup() {
  REPO="$BATS_TEST_DIRNAME/../.."
  export ESP_SYNC_SH="$REPO/lib/boot/esp-kernel-sync.sh"
  export STRAY_SH="$REPO/lib/boot/stray-kernel.sh"
  # shellcheck source=../../vm/lib/esp-resilience-verify.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/esp-resilience-verify.sh"
}

@test "verify passes when the real hardening guards all fire" {
  run esp_resilience_verify
  [ "$status" -eq 0 ]
}

@test "verify fails when a guard regresses (install_critical never fails)" {
  STUB="$(mktemp -d)/esp-kernel-sync.sh"
  cat >"$STUB" <<'EOF'
esp_sync_install_critical() { cp -f "$1" "$2" 2>/dev/null; return 0; }
[[ "${ESP_KERNEL_SYNC_LIB_ONLY:-0}" == "1" ]] && return 0
EOF
  ESP_SYNC_SH="$STUB" run esp_resilience_verify
  [ "$status" -ne 0 ]
}
