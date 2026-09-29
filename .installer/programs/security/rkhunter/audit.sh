# shellcheck shell=bash
# Feature Audit probe for rkhunter (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg rkhunter rkhunter || return 0
fa_as_root || return 0
fa_check rkhunter-config "configuration is valid" \
  rkhunter --config-check --nocolors
fa_check rkhunter-timer "scan timer enabled" \
  systemctl is-enabled --quiet rkhunter-scan.timer
fa_check rkhunter-propdb "file properties database built" \
  test -s /var/lib/rkhunter/db/rkhunter.dat
