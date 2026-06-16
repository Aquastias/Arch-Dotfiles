#!/usr/bin/env bats
# Tests for .os/lib/guided.sh — the Guided Installer's fzf shell (ADR 0039).
# The shell is impure glue, but its selection seam (guided_select /
# guided_prompt) is replayable: under a GUIDED_REPLAY answers file the menu
# is driven headlessly, no fzf, no tty. So guided_build — the assembly path —
# is exercised deterministically here; the fzf rendering stays smoke-only.
#
# Behaviour under test (external only — the Effective Config a replayed
# session assembles, and the INSTALL consent gate), never internal structure.

setup() {
  TEST_DIR="$(mktemp -d)"
  export OS_DIR="$TEST_DIR"

  # Mirror common.sh faithfully: info/warn/section echo to STDOUT, error to
  # stderr. guided_build's only stdout MUST be the Effective Config — any human
  # output (the review screen) has to be redirected, so these stdout stubs are
  # the guard that catches stdout pollution.
  info()    { echo "[info] $*"; }
  warn()    { echo "[warn] $*"; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { echo "== $* =="; }
  export -f info warn error section

  mkdir -p "$OS_DIR/hosts/core"
  printf '%s\n' \
    '{"system_programs":["cups"],"sysctl":{"vm.swappiness":10}}' \
    > "$OS_DIR/hosts/core/profile.jsonc"

  # Real pure cores (emit pulls in the real picker_assign_disks + layers).
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/emit.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"

  # Stub only the live-disk enumeration (no lsblk in tests); picker_assign_disks
  # stays real so the assembled config is the genuine artifact.
  live_medium_disks() { :; }
  picker_enum_disks() { printf '%s\n' "/dev/disk/by-id/wwn-0xDEAD"; }
  export -f live_medium_disks picker_enum_disks

  # shellcheck source=../../lib/guided.sh
  source "$BATS_TEST_DIRNAME/../../lib/guided.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

write_answers() {
  local f="$TEST_DIR/answers"
  printf '%s\n' "$@" > "$f"
  printf '%s' "$f"
}

# ── tracer: a replayed session assembles the single-disk Effective Config ───

@test "guided_build: a replayed session assembles the Effective Config" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  # stdout is the Effective Config; the review screen goes to stderr.
  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.system.hostname == "eterniox"'
  echo "$effective" | jq -e '.mode == "single"'
  echo "$effective" | jq -e '.disk == "/dev/disk/by-id/wwn-0xDEAD"'
  echo "$effective" | jq -e '.system_programs == ["cups"]'
}

# ── the config must carry the back-end's required identity fields ───────────
# (validation.sh requires system.locale + system.timezone; the tracer defaults
#  them — issue 05 turns these into live-system-picked menu rows.)

@test "guided_build: the config carries the required identity defaults" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  echo "$effective" | jq -e '.system.locale and .system.timezone'
  echo "$effective" | jq -e '.system.keymap'
}

# ── the interactive menu renders the Host/Users split with values + ● ───────
# _guided_menu_lines is the pure core the fzf loop displays; the fzf navigation
# itself is smoke-only.

@test "_guided_menu_lines: renders the Host/Users split, values, override flag" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"

  run _guided_menu_lines "$state"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "hostname: eterniox"   # edited value shown
  echo "$output" | grep -q "●"                     # overridden row flagged
  echo "$output" | grep -q "filesystem: zfs"       # Disks-first, zfs default
  echo "$output" | grep -q "Users"                 # the Host/Users split
}

# ── the re-entrant loop: select a field, edit it, return, Proceed ───────────
# fzf is stubbed (its selection driven by current state) so the loop's dispatch
# — render → select → edit → re-enter → Proceed — is exercised deterministically.

@test "_guided_menu_loop: edits hostname then Proceeds (fzf stubbed)" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"   # disk already picked

  # First pass (no hostname yet) → pick the hostname row; next pass → Proceed.
  fzf() {
    cat >/dev/null
    if [ -z "$(cfgstate_get "$_GUIDED_STATE" system.hostname)" ]; then
      echo "Host · hostname: (none)"
    else
      echo "Proceed ▸ review & install"
    fi
  }
  guided_prompt() { printf '%s' "newhost"; }
  export -f fzf guided_prompt

  _guided_menu_loop
  local rc=$?
  [ "$rc" -eq 0 ]
  [ "$(cfgstate_get "$_GUIDED_STATE" system.hostname)" = "newhost" ]
}

# ── the typed INSTALL is the sole consent gate ─────────────────────────────

@test "guided_build: aborts with no config when INSTALL is not typed" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=nope')"

  run guided_build
  [ "$status" -ne 0 ]
  # nothing installable leaks to stdout
  refute_json() { ! echo "$1" | jq -e 'has("mode")' 2>/dev/null; }
  refute_json "$(guided_build 2>/dev/null)"
}
