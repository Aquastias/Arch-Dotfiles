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
  gpu_ln="$(grep -n 'lib-chroot/gpu.sh' "$CONFIGURE" | head -1 | cut -d: -f1)"
  initcpio_ln="$(grep -n 'lib-chroot/initcpio.sh' "$CONFIGURE" \
    | head -1 | cut -d: -f1)"
  [ -n "$gpu_ln" ]
  [ -n "$initcpio_ln" ]
  [ "$gpu_ln" -lt "$initcpio_ln" ]
}
