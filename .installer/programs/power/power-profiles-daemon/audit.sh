# shellcheck shell=bash
# Feature Audit probe for power-profiles-daemon (ADR 0152; contract:
# PROGRAM_SPEC.md).
feature_audit_require_package power-profiles-daemon power-profiles-daemon \
  || return 0
feature_audit_as_root || return 0
feature_audit_check ppd-active "power-profiles-daemon.service active" \
  feature_audit_unit_active power-profiles-daemon
_probe_ppd_switch() {
  local was; was="$(powerprofilesctl get)" || return 1
  powerprofilesctl set power-saver \
    && [ "$(powerprofilesctl get)" = power-saver ] \
    && powerprofilesctl set "$was"
}
feature_audit_check ppd-switch "profiles switch and read back" _probe_ppd_switch
