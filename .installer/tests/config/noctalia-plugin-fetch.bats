#!/usr/bin/env bats
# _noc_vendor_plugin (lib/chroot/noctalia-preset.sh, ADR 0093): a Noctalia
# plugin fetch retries before giving up. Regression (Audit Run 20260929): one
# network blip dropped a dozen plugins on the kernels/greetd variants.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/chroot/noctalia-preset.sh"
  sleep() { :; }
  N="$BATS_TEST_TMPDIR/n"; echo 0 > "$N"
}

@test "a transient fetch failure is retried until it succeeds" {
  _noc_seed_plugin() { local n; n=$(($(cat "$N") + 1)); echo "$n" > "$N"
    ((n >= 2)); }
  run _noc_vendor_plugin repo ref keymap
  [ "$status" -eq 0 ]
  [ "$(cat "$N")" -eq 2 ]
}

@test "a persistent failure gives up after 3 tries" {
  _noc_seed_plugin() { echo $(($(cat "$N") + 1)) > "$N"; return 1; }
  run _noc_vendor_plugin repo ref keymap
  [ "$status" -ne 0 ]
  [ "$(cat "$N")" -eq 3 ]
}
