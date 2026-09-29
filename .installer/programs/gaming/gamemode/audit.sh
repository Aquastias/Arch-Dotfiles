# shellcheck shell=bash
# Feature Audit probe for gamemode (ADR 0152; contract: PROGRAM_SPEC.md).
# gamemoded's self-test needs cpufreq governors, which a VM does not expose.
fa_require_pkg gamemode gamemode || return 0
fa_as_user || return 0
fa_check gamemode-run "gamemoderun wraps a process" gamemoderun true
fa_check gamemode-daemon "gamemoded answers on the session bus" \
  gamemoded -s
if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
  fa_check gamemode-selftest "gamemoded self-test passes" \
    timeout 60 gamemoded -t
else
  fa_skip gamemode-selftest "no cpufreq governors in the VM"
fi
