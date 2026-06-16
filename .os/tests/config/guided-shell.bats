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

# queue <choice...> — script a sequence of fzf selections in a file, popped one
# per call by the fzf stub below. File-backed so it advances across the `… |
# fzf` subshell (a counter in the stub would only mutate the subshell). An
# empty queue returns non-zero, the same as an Esc, so a loop can never hang.
queue() { printf '%s\n' "$@" > "$TEST_DIR/queue"; }
fzf_queue() {
  fzf() {
    cat >/dev/null
    local q="$TEST_DIR/queue" line
    [ -s "$q" ] || return 1
    line="$(head -n1 "$q")"
    sed -i '1d' "$q"
    printf '%s\n' "$line"
  }
  export -f fzf
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

# ── Undo in the loop reverts an edit without losing the rest (non-destructive)
# fzf is stubbed to replay a scripted sequence of menu choices; the loop drives
# its dispatch deterministically (render → select → edit/undo → Proceed).

@test "_guided_menu_loop: editing then Undo reverts the edit, then Proceeds" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  # Pick the hostname row, then Undo, then Proceed.
  fzf_queue
  queue "Host · hostname: (none)" "Undo ◂ last change" \
        "Proceed ▸ review & install"
  guided_prompt() { printf '%s' "newhost"; }
  export -f guided_prompt

  _guided_menu_loop      # direct (not `run`) so state mutates in the test shell
  [ "$?" -eq 0 ]
  # the hostname edit was committed, then undone → back to unset
  [ -z "$(cfgstate_get "$_GUIDED_STATE" system.hostname)" ]
}

# ── Reset-all confirms first, then discards every override ──────────────────

@test "_guided_menu_loop: Reset-all (confirmed) discards the overrides" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  fzf_queue
  queue "Reset all ▸ discard every change" "Proceed ▸ review & install"
  guided_prompt() { printf '%s' "RESET"; }   # confirm the wipe
  export -f guided_prompt

  _guided_menu_loop
  [ "$?" -eq 0 ]
  [ -z "$(cfgstate_get "$_GUIDED_STATE" system.hostname)" ]   # override gone
}

@test "_guided_menu_loop: Reset-all (declined) keeps the overrides" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  fzf_queue
  queue "Reset all ▸ discard every change" "Proceed ▸ review & install"
  guided_prompt() { printf '%s' "no"; }      # decline the wipe
  export -f guided_prompt

  _guided_menu_loop
  [ "$?" -eq 0 ]
  [ "$(cfgstate_get "$_GUIDED_STATE" system.hostname)" = "eterniox" ]  # kept
}

# ── the footer surfaces undo/redo only when available, Reset-all always ─────
# _guided_footer_lines is the pure core the loop appends below the rows; the
# fzf draw is smoke-only.

@test "_guided_footer_lines: a fresh history offers only Reset-all" {
  h="$(hist_new "$(cfgstate_new)")"

  run _guided_footer_lines "$h"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Reset all"
  ! echo "$output" | grep -q "Undo"
  ! echo "$output" | grep -q "Redo"
}

@test "_guided_footer_lines: a committed change offers Undo (not Redo)" {
  h="$(hist_new "$(cfgstate_new)")"
  h="$(hist_commit "$h" "$(cfgstate_set "$(cfgstate_new)" mode '"single"')")"

  run _guided_footer_lines "$h"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Undo"
  echo "$output" | grep -q "Reset all"
  ! echo "$output" | grep -q "Redo"
}

@test "_guided_footer_lines: after an undo, Redo is offered" {
  h="$(hist_new "$(cfgstate_new)")"
  h="$(hist_commit "$h" "$(cfgstate_set "$(cfgstate_new)" mode '"single"')")"
  h="$(hist_undo "$h")"

  run _guided_footer_lines "$h"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Redo"
}

# ── Reset field in the loop: pick one overridden field and clear it (undoable)

@test "_guided_menu_loop: Reset field clears the picked override" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  fzf_queue
  queue "Reset field ▸ clear one field" "Proceed ▸ review & install"
  guided_select() { printf '%s' "system.hostname"; }   # pick the field to clear
  export -f guided_select

  _guided_menu_loop
  [ "$?" -eq 0 ]
  [ -z "$(cfgstate_get "$_GUIDED_STATE" system.hostname)" ]
}

# ── Reset section in the loop: clear every override in the picked section ────

@test "_guided_menu_loop: Reset section clears the picked section's overrides" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  _GUIDED_STATE="$(cfgstate_set "$_GUIDED_STATE" filesystem '"zfs"')"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  fzf_queue
  queue "Reset section ▸ clear one section" "Proceed ▸ review & install"
  guided_select() { printf '%s' "Host"; }              # pick the section
  export -f guided_select

  _guided_menu_loop
  [ "$?" -eq 0 ]
  [ -z "$(cfgstate_get "$_GUIDED_STATE" system.hostname)" ]
  [ -z "$(cfgstate_get "$_GUIDED_STATE" filesystem)" ]
}

# ── granular reset: a menu section's overrides clear, the rest survives ─────
# _guided_reset_section is pure (menu_rows + cfgstate_unset); it clears only the
# section's *menu* fields, so the seeded identity (not a row) is preserved.

@test "_guided_reset_section: clears a section's overrides, keeps the rest" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  state="$(cfgstate_set "$state" filesystem '"zfs"')"
  state="$(cfgstate_set "$state" system.locale '"de_DE.UTF-8"')"  # seeded, no row

  run _guided_reset_section "$state" Host
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system | has("hostname") | not'   # Host row cleared
  echo "$output" | jq -e 'has("filesystem") | not'           # Host row cleared
  echo "$output" | jq -e '.system.locale == "de_DE.UTF-8"'   # non-row preserved
}

# ── the granular reset actions appear only when there is something to clear ──

@test "_guided_reset_lines: offered only when the state carries overrides" {
  run _guided_reset_lines "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  run _guided_reset_lines "$state"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Reset field"
  echo "$output" | grep -q "Reset section"
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
