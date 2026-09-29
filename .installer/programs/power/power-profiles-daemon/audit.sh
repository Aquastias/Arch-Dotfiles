# shellcheck shell=bash
# Feature Audit probe for power-profiles-daemon (ADR 0152; contract:
# PROGRAM_SPEC.md).
fa_require_pkg power-profiles-daemon power-profiles-daemon || return 0
fa_as_root || return 0
fa_check ppd-active "power-profiles-daemon.service active" \
  fa_unit_active power-profiles-daemon
_fa_ppd_switch() {
  local was; was="$(powerprofilesctl get)" || return 1
  powerprofilesctl set power-saver && [ "$(powerprofilesctl get)" = power-saver ] \
    && powerprofilesctl set "$was"
}
fa_check ppd-switch "profiles switch and read back" _fa_ppd_switch
