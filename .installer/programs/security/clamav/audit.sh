# shellcheck shell=bash
# shellcheck disable=SC2016 # sh -c bodies expand in the child shell
# Feature Audit probe for clamav (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package clamav clamav || return 0
feature_audit_as_root || return 0
feature_audit_check clamav-daemon "clamav-daemon.service active" \
  feature_audit_unit_active clamav-daemon
feature_audit_check clamav-onacc "clamav-clamonacc.service active" \
  feature_audit_unit_active clamav-clamonacc
feature_audit_check clamav-timer "daily scan timer enabled" \
  systemctl is-enabled --quiet clamav-daily-scan.timer
feature_audit_check clamav-signatures "virus definitions present" \
  sh -c 'ls /var/lib/clamav/main.c[lv]d /var/lib/clamav/daily.c[lv]d'
# The real proof: the daemon flags the EICAR test string.
_probe_eicar() {
  local f; f="$(mktemp /tmp/fa-eicar.XXXX)"
  printf '%s%s' 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD' \
    '-ANTIVIRUS-TEST-FILE!$H+H*' > "$f"
  clamdscan --fdpass --no-summary "$f" 2>&1 | grep -q FOUND; local rc=$?
  rm -f "$f"; return "$rc"
}
feature_audit_check clamav-detects "clamd detects EICAR" _probe_eicar
