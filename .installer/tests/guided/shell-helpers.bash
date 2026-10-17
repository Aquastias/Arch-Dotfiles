# shell-helpers.bash — shared setup for the shell-*.bats parts
# Tests for .installer/lib/guided/shell.sh — the Guided Installer's fzf shell (ADR
# 0039).
# The shell is impure glue, but its selection seam (guided_select /
# guided_prompt) is replayable: under a GUIDED_REPLAY answers file the menu
# is driven headlessly, no fzf, no tty. So guided_build — the assembly path —
# is exercised deterministically here; the fzf rendering stays smoke-only.
#
# Behaviour under test (external only — the Effective Config a replayed
# session assembles, and the INSTALL consent gate), never internal structure.

setup() {
  TEST_DIR="$(mktemp -d)"
  export INSTALLER_DIR="$TEST_DIR"

  # Mirror common.sh faithfully: info/warn/section echo to STDOUT, error to
  # stderr. guided_build's only stdout MUST be the Effective Config — any human
  # output (the review screen) has to be redirected, so these stdout stubs are
  # the guard that catches stdout pollution.
  info()    { echo "[info] $*"; }
  warn()    { echo "[warn] $*"; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { echo "== $* =="; }
  export -f info warn error section

  mkdir -p "$INSTALLER_DIR/hosts/core"
  printf '%s\n' \
    '{"host_programs":["cups"],"sysctl":{"vm.swappiness":10}}' \
    > "$INSTALLER_DIR/hosts/core/profile.jsonc"

  # Real pure cores (emit pulls in the real picker_assign_disks + layers).
  source "$BATS_TEST_DIRNAME/../../lib/config/config-state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/emit.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"

  # Stub only the live-disk enumeration (no lsblk in tests); picker_assign_disks
  # stays real so the assembled config is the genuine artifact.
  live_medium_disks() { :; }
  picker_enum_disks() { printf '%s\n' "/dev/disk/by-id/wwn-0xDEAD"; }
  export -f live_medium_disks picker_enum_disks

  # shellcheck source=../../lib/guided/shell.sh
  source "$BATS_TEST_DIRNAME/../../lib/guided/shell.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# write_answers <key=value…> — a replay answers file. A blank session presets
# no user and an install refuses without one (ADR 0157), so a `tester` user is
# created unless the answers pick (`users=`) or create (`new_user_name=`) one.
write_answers() {
  local answers_file="$TEST_DIR/answers"
  printf '%s\n' "$@" > "$answers_file"
  grep -qE '^(users|new_user_name)=' "$answers_file" \
    || printf '%s\n' new_user_name=tester >> "$answers_file"
  printf '%s' "$answers_file"
}


# assert_extras_off <config> — no Security & Backup Extra is on (absent or off).
assert_extras_off() {
  jq -e '(.post_install.security.firewall // "none") == "none"
    and ([.post_install // {} | .. | booleans | select(.)] | length) == 0' \
    <<<"$1" >/dev/null
}
