# shellcheck shell=bash
# Feature Audit probe for tuned (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package tuned tuned || return 0
feature_audit_as_root || return 0
feature_audit_check tuned-active "tuned.service active" feature_audit_unit_active tuned
feature_audit_check tuned-profile "a tuned profile is active" \
  sh -c 'tuned-adm active | grep -q "Current active profile"'
feature_audit_check tuned-ppd "tuned-ppd provides the ppd D-Bus API" \
  feature_audit_unit_active tuned-ppd
