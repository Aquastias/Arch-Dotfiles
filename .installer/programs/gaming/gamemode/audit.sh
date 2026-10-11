# shellcheck shell=bash
# Feature Audit probe for gamemode (ADR 0152; contract: PROGRAM_SPEC.md).
# gamemoded's self-test needs cpufreq governors, which a VM does not expose.
feature_audit_require_package gamemode gamemode || return 0
feature_audit_as_user || return 0
feature_audit_check gamemode-run "gamemoderun wraps a process" gamemoderun true
feature_audit_check gamemode-daemon "gamemoded answers on the session bus" \
  gamemoded -s
if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
  feature_audit_check gamemode-selftest "gamemoded self-test passes" \
    timeout 60 gamemoded -t
else
  feature_audit_skip gamemode-selftest "no cpufreq governors in the VM"
fi
