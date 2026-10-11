# shellcheck shell=bash
# shellcheck disable=SC2016 # sh -c bodies expand in the child shell
# Feature Audit probe for apparmor (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package apparmor apparmor || return 0
feature_audit_as_root || return 0
feature_audit_check apparmor-kernel "LSM enabled in the running kernel" \
  grep -qw apparmor /sys/kernel/security/lsm
feature_audit_check apparmor-service \
  "apparmor.service active" feature_audit_unit_active apparmor
feature_audit_check apparmor-enabled "aa-enabled says Yes" \
  sh -c '[ "$(aa-enabled 2>&1)" = Yes ]'
feature_audit_check apparmor-profiles "profiles loaded" \
  sh -c '[ "$(aa-status --profiled 2>/dev/null || echo 0)" -gt 0 ]'
