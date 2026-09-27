#!/usr/bin/env bats
# security/clamav program. Static seam like nvim-program.bats: assert the
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
_line() { grep -nE "$1" "$INSTALL" | head -1 | cut -d: -f1; }

@test "clamav install seeds the signature DB with freshclam" {
  grep -qE '^[^#]*sudo freshclam' "$INSTALL"
}

@test "clamav install runs freshclam before enabling clamav-daemon" {
  local f e
  f="$(_line '^[^#]*sudo freshclam')"
  e="$(_line 'systemctl enable clamav-daemon')"
  [ -n "$f" ]
  [ -n "$e" ]
  (( f < e ))
}

@test "clamav install tolerates a failed freshclam (CDN/offline)" {
  _joined | grep -qE '^[^#]*sudo freshclam.*\|\|'
}

@test "clamav install creates freshclam.log 600 clamav-owned (UpdateLogFile)" {
  _joined \
    | grep -qE 'install .*-o clamav .*-m 600 .*/var/log/clamav/freshclam.log'
}
