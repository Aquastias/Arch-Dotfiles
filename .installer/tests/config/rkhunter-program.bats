#!/usr/bin/env bats
# security/rkhunter program — when the file-properties baseline is refreshed.

setup() {
  PROG="$BATS_TEST_DIRNAME/../../programs/security/rkhunter"
  INSTALL="$PROG/install.sh"
  SCAN="$PROG/scripts/rkhunter_scan.sh"
  PROPUPD="$PROG/scripts/rkhunter_propupd.sh"
}

@test "the scheduled scan never re-baselines right before it checks" {
  # `--propupd` before `--check` accepted every changed binary as the new
  # baseline, so file-property tampering could never be reported.
  ! grep -q -- '--propupd' "$SCAN"
}

@test "the baseline is refreshed after each pacman transaction instead" {
  # Package upgrades change files legitimately; re-baselining at upgrade time
  # keeps the daily check from alarming on them.
  grep -q 'rkhunter-propupd.hook' "$INSTALL"
  grep -q '^Exec = /usr/local/lib/rkhunter/rkhunter_propupd.sh$' "$INSTALL"
  grep -qF '"$RKHUNTER_SCRIPTS/rkhunter_propupd.sh"' "$INSTALL"
  grep -q 'When = PostTransaction' "$INSTALL"
}

@test "the baseline refresh drops only rkhunter's own grep warnings" {
  # rkhunter's scripts trip GNU grep's stray-backslash and egrep warnings:
  # upstream noise in every upgrade's output. Real messages pass through.
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  cat >"$bin/rkhunter" <<'STUB'
#!/usr/bin/env bash
[[ "$*" == "--propupd -q" ]] || exit 9
echo 'grep: warning: stray \ before -' >&2
echo 'egrep: warning: egrep is obsolescent; using grep -E' >&2
echo 'Invalid SCRIPTWHITELIST configuration option'
exit 1
STUB
  chmod +x "$bin/rkhunter"
  PATH="$bin:$PATH" run "$PROPUPD"
  [ "$status" -eq 0 ]
  [ "$output" = 'Invalid SCRIPTWHITELIST configuration option' ]
}
