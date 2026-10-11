# shellcheck shell=bash
# Feature Audit probe for rkhunter (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package rkhunter rkhunter || return 0
feature_audit_as_root || return 0
feature_audit_check rkhunter-config "configuration is valid" \
  rkhunter --config-check --nocolors
feature_audit_check rkhunter-timer "scan timer enabled" \
  systemctl is-enabled --quiet rkhunter-scan.timer
feature_audit_check rkhunter-propdb "file properties database built" \
  test -s /var/lib/rkhunter/db/rkhunter.dat
