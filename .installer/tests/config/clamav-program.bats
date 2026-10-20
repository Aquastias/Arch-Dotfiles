#!/usr/bin/env bats
# security/clamav program. Static seam like nvim-program-*.bats: assert the
# COMMITTED install.sh, no install run. First-boot ordering per the Arch Wiki
# ClamAV page: freshclam must seed the signature DB before clamd first starts —
# clamav-daemon.service skips itself (ConditionPathExistsGlob on main/daily)
# with no DB, leaving clamonacc nothing to attach to on first boot.

setup() {
  INSTALL="$BATS_TEST_DIRNAME/../../programs/security/clamav/install.sh"
}

# _joined — install.sh with `\` continuations and leading-`||` lines folded
# into the command they continue, so multi-line commands grep as one.
_joined() {
  awk '
    /^[[:space:]]*\|\|/ { sub(/^[[:space:]]*/, " "); buf = buf $0; next }
    { if (buf != "") print buf; buf = $0 }
    buf ~ /\\$/ { sub(/\\$/, "", buf); getline nx; buf = buf nx }
    END { if (buf != "") print buf }
  ' "$INSTALL"
}

# _line <regex> — first line number in install.sh matching <regex>.
_line() { PATTERN="$1" awk '$0 ~ ENVIRON["PATTERN"] { print NR; exit }' "$INSTALL"; }

@test "clamav install seeds the signature DB with freshclam" {
  grep -qE '^[^#]*sudo freshclam' "$INSTALL"
}

@test "clamav install runs freshclam before enabling clamav-daemon" {
  local freshclam_line enable_line
  freshclam_line="$(_line '^[^#]*sudo freshclam')"
  enable_line="$(_line 'systemctl enable clamav-daemon')"
  [ -n "$freshclam_line" ]
  [ -n "$enable_line" ]
  (( freshclam_line < enable_line ))
}

@test "clamav install tolerates a failed freshclam (CDN/offline)" {
  _joined | grep -qE '^[^#]*sudo freshclam.*\|\|'
}

@test "clamav install creates freshclam.log 600 clamav-owned (UpdateLogFile)" {
  _joined \
    | grep -qE 'install .*-o clamav .*-m 600 .*/var/log/clamav/freshclam.log'
}

@test "daily scan alert passes send_user_notification arguments in order" {
  # The log hint landed in the icon slot and the app name in the timeout slot,
  # so `notify-send -t "ClamAV Daily Scan"` failed and the alert never showed.
  local work="$BATS_TEST_TMPDIR" scan
  scan="$BATS_TEST_DIRNAME/../../programs/security/clamav/scripts"
  scan+="/clamav_daily_scan.sh"
  cat >"$work/stdlib.sh" <<'STUB'
send_user_notification() { printf '%s\n' "$@" >"$NOTIFY_ARGS"; }
clamscan() { printf 'Infected files: 2\n'; }
loginctl() { :; }
STUB
  local scan_text stdlib=/usr/local/lib/shell-stdlib.sh
  scan_text="$(<"$scan")"
  printf '%s\n' "${scan_text//"$stdlib"/"$work/stdlib.sh"}" >"$work/scan.sh"
  NOTIFY_ARGS="$work/args" run bash "$work/scan.sh"
  mapfile -t args <"$work/args"
  [ "${args[2]}" = "clamav" ]             # icon
  [ "${args[3]}" = "ClamAV Daily Scan" ]  # app name
  [[ "${args[4]}" =~ ^[0-9]+$ ]]          # timeout (ms)
  [[ "${args[1]}" == *"2 infected"*"/tmp/clamav-scan-"* ]]
}
