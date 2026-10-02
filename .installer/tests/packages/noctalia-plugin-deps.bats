#!/usr/bin/env bats
# noctalia_plugin_deps (lib/packages/niri.sh, ADR 0093/0097): the repo
# packages a Noctalia plugin's tools need.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/packages/niri.sh"
}

@test "no plugin pulls a power daemon (options.power.profile owns it)" {
  # Regression (Audit Run 20260929): gamer-mode / battery-power-management
  # pulled power-profiles-daemon, which conflicts with the tuned backend's
  # tuned-ppd and overrides `profile: none` (ADR 0080).
  local pl
  for pl in gamer-mode battery-power-management; do
    run noctalia_plugin_deps "$pl"
    [[ "$output" != *power-profiles-daemon* ]]
    [[ "$output" != *tuned* ]]
  done
}

@test "battery-power-management still pulls upower" {
  run noctalia_plugin_deps battery-power-management
  [ "$output" = upower ]
}
