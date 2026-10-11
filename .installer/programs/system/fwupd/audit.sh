# shellcheck shell=bash
# Feature Audit probe for fwupd (ADR 0152; contract: PROGRAM_SPEC.md).
# Updating firmware needs real updatable devices (unverifiable in a VM).
feature_audit_require_package fwupd fwupd || return 0
feature_audit_as_root || return 0
feature_audit_check fwupd-timer "fwupd-refresh.timer enabled" \
  systemctl is-enabled --quiet fwupd-refresh.timer
feature_audit_check fwupd-devices "fwupdmgr lists devices" \
  sh -c 'fwupdmgr get-devices --json >/dev/null'
if [[ "$FA_ONLINE" == 1 ]]; then
  feature_audit_check fwupd-refresh "metadata refresh works" \
    sh -c 'fwupdmgr refresh --force >/dev/null'
fi
