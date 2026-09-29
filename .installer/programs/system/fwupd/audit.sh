# shellcheck shell=bash
# Feature Audit probe for fwupd (ADR 0152; contract: PROGRAM_SPEC.md).
# Updating firmware needs real updatable devices (unverifiable in a VM).
fa_require_pkg fwupd fwupd || return 0
fa_as_root || return 0
fa_check fwupd-timer "fwupd-refresh.timer enabled" \
  systemctl is-enabled --quiet fwupd-refresh.timer
fa_check fwupd-devices "fwupdmgr lists devices" \
  sh -c 'fwupdmgr get-devices --json >/dev/null'
if [[ "$FA_ONLINE" == 1 ]]; then
  fa_check fwupd-refresh "metadata refresh works" \
    sh -c 'fwupdmgr refresh --force >/dev/null'
fi
