# shellcheck shell=bash
# shellcheck disable=SC2016 # sh -c bodies expand in the child shell
# Feature Audit probe for clamav (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg clamav clamav || return 0
fa_as_root || return 0
fa_check clamav-daemon "clamav-daemon.service active" \
  fa_unit_active clamav-daemon
fa_check clamav-onacc "clamav-clamonacc.service active" \
  fa_unit_active clamav-clamonacc
fa_check clamav-timer "daily scan timer enabled" \
  systemctl is-enabled --quiet clamav-daily-scan.timer
fa_check clamav-signatures "virus definitions present" \
  sh -c 'ls /var/lib/clamav/main.c[lv]d /var/lib/clamav/daily.c[lv]d'
# The real proof: the daemon flags the EICAR test string.
_fa_eicar() {
  local f; f="$(mktemp /tmp/fa-eicar.XXXX)"
  printf '%s' 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > "$f"
  clamdscan --fdpass --no-summary "$f" 2>&1 | grep -q FOUND; local rc=$?
  rm -f "$f"; return "$rc"
}
fa_check clamav-detects "clamd detects EICAR" _fa_eicar
