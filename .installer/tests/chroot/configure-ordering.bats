#!/usr/bin/env bats
# Guards the load-bearing chroot ordering (ADR 0053): the GPU Configuration
# Module must run BEFORE initcpio so the single `mkinitcpio -P` bakes in the
# Early-KMS MODULES + modprobe.d. Running after the build would silently drop
# Early KMS, so this ordering is asserted directly.

setup() {
  CONFIGURE="$BATS_TEST_DIRNAME/../../lib/chroot/configure.sh"
}

@test "configure.sh runs gpu.sh before initcpio.sh" {
  local gpu_ln initcpio_ln
  gpu_ln="$(awk '/lib-chroot\/gpu.sh/ { print NR; exit }' "$CONFIGURE")"
  initcpio_ln="$(awk '/lib-chroot\/initcpio.sh/ { print NR; exit }' \
    "$CONFIGURE")"
  [ -n "$gpu_ln" ]
  [ -n "$initcpio_ln" ]
  [ "$gpu_ln" -lt "$initcpio_ln" ]
}
