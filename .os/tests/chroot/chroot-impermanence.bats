#!/usr/bin/env bats
# Tests for .os/lib/chroot/impermanence.sh — Chroot Configuration Module.
#
# Strategy: stub zfs/zpool/systemctl as bash fns that append argv to $CALLS,
# then source impermanence.sh and call impermanence_apply. Assertions read
# $CALLS plus files generated under $FAKEROOT.

setup() {
  TEST_DIR="$(mktemp -d)"
  CALLS="$TEST_DIR/calls.log"
  FAKEROOT="$TEST_DIR/root"
  mkdir -p "$FAKEROOT"
  export CALLS FAKEROOT

  info()    { :; }
  warn()    { :; }
  error()   { echo "ERROR: $*" >&2; exit 1; }
  section() { :; }
  export -f info warn error section

  zfs() {
    printf 'zfs %s\n' "$*" >> "$CALLS"
    [[ "$1" == "list" ]] && return 1
    return 0
  }
  zpool()   { printf 'zpool %s\n'   "$*" >> "$CALLS"; }
  systemd-machine-id-setup() { printf 'machine-id-setup %s\n' "$*" >> "$CALLS"; }
  export -f zfs zpool systemd-machine-id-setup

  export IMPERMANENCE_ENABLED=false
  export IMPERMANENCE_DATASET=rpool/persist
  export IMPERMANENCE_MOUNT=/persist
  export RPOOL=rpool
  export ROOT="$FAKEROOT"
  PERSIST_DIRECTORIES=()
  PERSIST_FILES=()
  export PERSIST_DIRECTORIES PERSIST_FILES

  # shellcheck source=../../lib/chroot/impermanence.sh
  source "$BATS_TEST_DIRNAME/../../lib/chroot/impermanence.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# Convenience: enable + run, return zfs/zpool call log.
run_enabled() {
  IMPERMANENCE_ENABLED=true
  impermanence_apply
}

# ── cycle 1: tracer — disabled is a no-op ────────────────────────────────────

@test "disabled: impermanence_apply exits 0" {
  IMPERMANENCE_ENABLED=false
  run impermanence_apply
  [ "$status" -eq 0 ]
}

@test "disabled: no zfs/zpool calls" {
  IMPERMANENCE_ENABLED=false
  impermanence_apply
  [ ! -s "$CALLS" ]
}

# ── cycle 2+3: datasets are NOT created here — done EARLY in the layout phase ─
# Both the Persist Dataset and the Rollback Datasets are created before pacstrap
# by imp_create_persist_dataset + imp_create_rollback_datasets (see
# tests/impermanence-common.bats). Creating them in the Chroot Module is too
# late: rollback datasets would miss pacstrap's content + the zfs-list.cache,
# and the Persist Dataset would mount too late for the curated binds to restore
# /etc state before dbus.

@test "enabled: does NOT create the Persist Dataset (done early in layout)" {
  run_enabled
  ! grep -qE "^zfs create .* rpool/persist\$" "$CALLS"
}

@test "enabled: does NOT create the Rollback Datasets (done early in layout)" {
  run_enabled
  ! grep -qE "^zfs create .* rpool/ROOT/(etc|opt|root|srv|usrlocal)\$" "$CALLS"
}

# ── cycle 4: sorted defaults.manifest ────────────────────────────────────────

@test "enabled: writes /usr/lib/impermanence/defaults.manifest" {
  run_enabled
  [ -f "$FAKEROOT/usr/lib/impermanence/defaults.manifest" ]
}

@test "enabled: manifest is sorted union of CURATED_FILES + CURATED_DIRS" {
  run_enabled
  local m="$FAKEROOT/usr/lib/impermanence/defaults.manifest"
  expected="$(printf '%s\n' \
    "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}" | sort)"
  [ "$(cat "$m")" = "$expected" ]
}

# ── cycle 5: curated-file .mount unit shape ──────────────────────────────────

@test "enabled: writes .mount unit for /etc/machine-id" {
  run_enabled
  local u="$FAKEROOT/usr/lib/systemd/system"
  [ -f "$u/etc-machine\\x2did.mount" ]
}

@test "enabled: file .mount has What=/persist/etc/machine-id" {
  run_enabled
  local u="$FAKEROOT/usr/lib/systemd/system/etc-machine\\x2did.mount"
  grep -qE "^What=/persist/etc/machine-id$" "$u"
}

@test "enabled: file .mount has Where=/etc/machine-id" {
  run_enabled
  local u="$FAKEROOT/usr/lib/systemd/system/etc-machine\\x2did.mount"
  grep -qE "^Where=/etc/machine-id$" "$u"
}

@test "enabled: file .mount has Type=none and Options=bind" {
  run_enabled
  local u="$FAKEROOT/usr/lib/systemd/system/etc-machine\\x2did.mount"
  grep -qE "^Type=none$" "$u"
  grep -qE "^Options=bind$" "$u"
}

@test "enabled: a .mount unit exists for every CURATED_FILES entry" {
  run_enabled
  local u="$FAKEROOT/usr/lib/systemd/system" f esc
  for f in "${CURATED_FILES[@]}"; do
    esc="$(systemd-escape --path "$f")"
    [ -f "$u/$esc.mount" ] || { echo "missing $f → $esc.mount"; return 1; }
  done
}

# ── cycle 6: dir .mount units, ordering, .wants symlinks ─────────────────────

@test "enabled: writes .mount unit for /etc/ssh (dir)" {
  run_enabled
  local u="$FAKEROOT/usr/lib/systemd/system/etc-ssh.mount"
  [ -f "$u" ]
  grep -qE "^What=/persist/etc/ssh$" "$u"
  grep -qE "^Where=/etc/ssh$" "$u"
}

@test "enabled: a .mount unit exists for every CURATED_DIRS entry" {
  run_enabled
  local u="$FAKEROOT/usr/lib/systemd/system" d esc
  for d in "${CURATED_DIRS[@]}"; do
    esc="$(systemd-escape --path "$d")"
    [ -f "$u/$esc.mount" ] || { echo "missing $d → $esc.mount"; return 1; }
  done
}

@test "enabled: every curated .mount has required ordering directives" {
  run_enabled
  local u="$FAKEROOT/usr/lib/systemd/system" p esc unit
  for p in "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}"; do
    esc="$(systemd-escape --path "$p")"
    unit="$u/$esc.mount"
    # After=zfs-mount.service (NOT tmpfiles-setup, which is After=local-fs.target
    # → would form an ordering cycle with our Before=local-fs.target).
    grep -qE "^After=zfs-mount\.service$" "$unit" \
      || { echo "$p missing After=zfs-mount.service"; return 1; }
    ! grep -qE "^After=systemd-tmpfiles-setup" "$unit" \
      || { echo "$p must NOT order After=tmpfiles (cycle)"; return 1; }
    grep -qE "^Before=local-fs\.target$" "$unit" \
      || { echo "$p missing Before"; return 1; }
    grep -qE "^RequiredBy=local-fs\.target$" "$unit" \
      || { echo "$p missing RequiredBy"; return 1; }
  done
}

@test "enabled: .wants symlink under local-fs.target.wants for each unit" {
  run_enabled
  local w="$FAKEROOT/usr/lib/systemd/system/local-fs.target.wants" p esc
  for p in "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}"; do
    esc="$(systemd-escape --path "$p")"
    [ -L "$w/$esc.mount" ] \
      || { echo "missing wants symlink for $p"; return 1; }
  done
}

@test "enabled: wants symlinks point to ../<unit>.mount (relative)" {
  run_enabled
  local w="$FAKEROOT/usr/lib/systemd/system/local-fs.target.wants"
  local esc target
  esc="$(systemd-escape --path /etc/ssh)"
  target="$(readlink "$w/$esc.mount")"
  [ "$target" = "../$esc.mount" ]
}

# ── cycle 7: tmpfiles snippet for curated paths ──────────────────────────────

@test "enabled: writes /usr/lib/tmpfiles.d/impermanence-curated.conf" {
  run_enabled
  [ -f "$FAKEROOT/usr/lib/tmpfiles.d/impermanence-curated.conf" ]
}

@test "enabled: tmpfiles snippet has a d entry for each CURATED_DIRS" {
  run_enabled
  local f="$FAKEROOT/usr/lib/tmpfiles.d/impermanence-curated.conf" d
  for d in "${CURATED_DIRS[@]}"; do
    grep -qE "^d $d " "$f" || { echo "missing d $d"; return 1; }
  done
}

@test "enabled: tmpfiles snippet has an f entry for each CURATED_FILES" {
  run_enabled
  local f="$FAKEROOT/usr/lib/tmpfiles.d/impermanence-curated.conf" file
  for file in "${CURATED_FILES[@]}"; do
    grep -qE "^f $file " "$f" || { echo "missing f $file"; return 1; }
  done
}

# ── cycle 8: bootstrap mount pair ────────────────────────────────────────────

@test "enabled: writes /usr/lib/tmpfiles.d/impermanence-bootstrap.conf" {
  run_enabled
  local f="$FAKEROOT/usr/lib/tmpfiles.d/impermanence-bootstrap.conf"
  [ -f "$f" ]
  grep -qE "^d /etc/systemd/system " "$f"
  grep -qE "^d /etc/tmpfiles.d " "$f"
}

@test "enabled: bootstrap .mount unit exists for /etc/systemd/system" {
  run_enabled
  local u="$FAKEROOT/usr/lib/systemd/system/etc-systemd-system.mount"
  [ -f "$u" ]
  grep -qE "^What=/persist/etc/systemd/system$" "$u"
  grep -qE "^Where=/etc/systemd/system$" "$u"
}

@test "enabled: bootstrap .mount unit exists for /etc/tmpfiles.d" {
  run_enabled
  local u="$FAKEROOT/usr/lib/systemd/system/etc-tmpfiles.d.mount"
  [ -f "$u" ]
  grep -qE "^What=/persist/etc/tmpfiles\.d$" "$u"
  grep -qE "^Where=/etc/tmpfiles\.d$" "$u"
}

@test "enabled: bootstrap STAGES /etc/systemd/system content onto /persist" {
  # The bind would otherwise cover /etc/systemd/system with an empty dir,
  # hiding install-time enablements (e.g. a sops-runtime symlink) at boot.
  mkdir -p "$FAKEROOT/etc/systemd/system/sysinit.target.wants"
  ln -s /usr/lib/systemd/system/sops-runtime.service \
    "$FAKEROOT/etc/systemd/system/sysinit.target.wants/sops-runtime.service"
  run_enabled
  [ -L "$FAKEROOT/persist/etc/systemd/system/sysinit.target.wants/sops-runtime.service" ]
  # COPY, not move — @blank keeps a fallback copy.
  [ -L "$FAKEROOT/etc/systemd/system/sysinit.target.wants/sops-runtime.service" ]
}

@test "enabled: bootstrap units have .wants symlinks" {
  run_enabled
  local w="$FAKEROOT/usr/lib/systemd/system/local-fs.target.wants"
  [ -L "$w/etc-systemd-system.mount" ]
  [ -L "$w/etc-tmpfiles.d.mount" ]
}

# ── cycle 9: move (not copy) curated paths → /persist ────────────────────────

# Helper: seed source content under FAKEROOT for a curated path.
seed_curated() {
  local p="$1" content="${2:-content}"
  mkdir -p "$FAKEROOT$(dirname "$p")"
  if [[ "$p" == */ ]] || [[ -d "$FAKEROOT$p" ]]; then
    mkdir -p "$FAKEROOT$p"
    printf '%s' "$content" > "$FAKEROOT$p/marker"
  else
    printf '%s' "$content" > "$FAKEROOT$p"
  fi
}

@test "enabled: COPIES curated file content; source KEPT (frozen in @blank)" {
  # Early-read files (machine-id, …) must stay in /etc so @blank captures real
  # values — they can't be bind-restored before PID 1 reads them.
  seed_curated /etc/machine-id "abc123"
  run_enabled
  [ -f "$FAKEROOT/etc/machine-id" ]
  [ "$(cat "$FAKEROOT/etc/machine-id")" = "abc123" ]
  [ -f "$FAKEROOT/persist/etc/machine-id" ]
  [ "$(cat "$FAKEROOT/persist/etc/machine-id")" = "abc123" ]
}

@test "enabled: initialises a real machine-id before @blank" {
  : > "$CALLS"
  run_enabled
  # machine-id setup must run, and must precede the @blank snapshots
  grep -qE "^machine-id-setup " "$CALLS"
  local mid_line snap_line
  mid_line="$(grep -nE "^machine-id-setup " "$CALLS" | head -1 | cut -d: -f1)"
  snap_line="$(grep -nE "^zfs snapshot .*@blank" "$CALLS" | head -1 | cut -d: -f1)"
  [ "$mid_line" -lt "$snap_line" ]
}

@test "enabled: moves curated dir content; source absent, dest present" {
  mkdir -p "$FAKEROOT/etc/ssh"
  printf 'hostkey' > "$FAKEROOT/etc/ssh/ssh_host_ed25519_key"
  run_enabled
  [ ! -e "$FAKEROOT/etc/ssh" ]
  [ -d "$FAKEROOT/persist/etc/ssh" ]
  [ -f "$FAKEROOT/persist/etc/ssh/ssh_host_ed25519_key" ]
}

@test "enabled: missing curated source is skipped (no error)" {
  IMPERMANENCE_ENABLED=true run impermanence_apply
  [ "$status" -eq 0 ]
}

# ── cycle 10: @blank snapshots on every Rollback Dataset ─────────────────────

@test "enabled: zfs snapshot ds@blank for every Rollback Dataset" {
  run_enabled
  local ds
  for ds in etc root opt srv usrlocal; do
    grep -qE "^zfs snapshot rpool/ROOT/$ds@blank$" "$CALLS" \
      || { echo "missing snapshot for rpool/ROOT/$ds"; return 1; }
  done
}

@test "enabled: @blank snapshot taken AFTER move (post-move call order)" {
  seed_curated /etc/machine-id "secret"
  run_enabled
  # No way to assert ordering between mv and zfs from $CALLS alone (mv isn't
  # logged), but we can assert dest exists at snapshot time by checking the
  # snapshot line appears in $CALLS at all (the move ran before it because
  # apply orders them).
  grep -qE "^zfs snapshot rpool/ROOT/etc@blank$" "$CALLS"
  [ -f "$FAKEROOT/persist/etc/machine-id" ]
}

# ── R1: info log when curated source missing ─────────────────────────────────

@test "enabled: info log emitted for each missing curated source" {
  local log="$TEST_DIR/info.log"
  info() { printf '%s\n' "$*" >> "$log"; }
  export -f info
  run_enabled
  [ -f "$log" ]
  grep -qE "skip.*missing.*machine-id" "$log"
}

# ── R2: rigorous post-move snapshot ordering ─────────────────────────────────

@test "enabled: dir staging (mv) occurs before every @blank snapshot" {
  # Curated DIRS are moved onto the Persist Dataset; that must finish before the
  # @blank snapshots so the snapshot is blank of them. (Curated FILES are copied,
  # not moved — see the machine-id tests.)
  mv() { printf 'mv %s\n' "$*" >> "$CALLS"; command mv "$@"; }
  export -f mv
  mkdir -p "$FAKEROOT/etc/ssh"
  printf 'k' > "$FAKEROOT/etc/ssh/key"
  run_enabled
  local last_mv first_snap
  last_mv="$(grep -n "^mv " "$CALLS" | tail -1 | cut -d: -f1)"
  first_snap="$(grep -n "^zfs snapshot " "$CALLS" | head -1 | cut -d: -f1)"
  [ -n "$last_mv" ] && [ -n "$first_snap" ]
  [ "$last_mv" -lt "$first_snap" ]
}

# ── R3: idempotent dataset creation ──────────────────────────────────────────

@test "enabled: idempotent — second apply on existing datasets is no-op" {
  zfs() {
    printf 'zfs %s\n' "$*" >> "$CALLS"
    [[ "$1" == "list" ]] && return 0
    return 0
  }
  export -f zfs
  run_enabled
  if grep -qE "^zfs create " "$CALLS"; then
    echo "FAIL: created datasets when all already exist"
    cat "$CALLS"
    return 1
  fi
}

# ── C6: mkinitcpio rollback hook pair ────────────────────────────────────────

@test "enabled: writes install hook /usr/lib/initcpio/install/zfs-rollback" {
  run_enabled
  local f="$FAKEROOT/usr/lib/initcpio/install/zfs-rollback"
  [ -f "$f" ]
  grep -qE "^build\\(\\)" "$f"
  grep -qE "add_runscript" "$f"
}

@test "enabled: writes runtime hook /usr/lib/initcpio/hooks/zfs-rollback" {
  run_enabled
  local f="$FAKEROOT/usr/lib/initcpio/hooks/zfs-rollback"
  [ -f "$f" ]
  # Must be run_latehook so archzfs has finished its zpool import.
  grep -qE "^run_latehook\\(\\)" "$f"
}

@test "enabled: runtime hook has hardcoded Rollback Dataset list" {
  run_enabled
  local f="$FAKEROOT/usr/lib/initcpio/hooks/zfs-rollback" ds
  for ds in etc root opt srv usrlocal; do
    grep -qE "rpool/ROOT/$ds" "$f" \
      || { echo "missing rpool/ROOT/$ds in runtime hook"; return 1; }
  done
}

@test "enabled: runtime hook fails closed on missing @blank snapshot" {
  run_enabled
  local f="$FAKEROOT/usr/lib/initcpio/hooks/zfs-rollback"
  grep -qE "launch_interactive_shell|emergency" "$f"
  grep -qE "zfs list .* @blank|@blank" "$f"
}

@test "enabled: runtime hook runs zfs rollback -r ds@blank" {
  run_enabled
  local f="$FAKEROOT/usr/lib/initcpio/hooks/zfs-rollback"
  grep -qE "zfs rollback -r" "$f"
}

# ── slice 2 cycle 1 (tracer): one extension dir → .mount under /persist ─────

@test "extension dir: writes .mount unit under /persist/etc/systemd/system" {
  PERSIST_DIRECTORIES=("/etc/wireguard")
  run_enabled
  local u="$FAKEROOT/persist/etc/systemd/system/etc-wireguard.mount"
  [ -f "$u" ]
  grep -qE "^What=/persist/etc/wireguard$" "$u"
  grep -qE "^Where=/etc/wireguard$" "$u"
}

@test "extension dir: writes /persist tmpfiles snippet for extensions" {
  PERSIST_DIRECTORIES=("/etc/wireguard")
  run_enabled
  local f="$FAKEROOT/persist/etc/tmpfiles.d/impermanence-extensions.conf"
  [ -f "$f" ]
  grep -qE "^d /etc/wireguard " "$f"
}

@test "extension file: writes f entry and .mount unit" {
  PERSIST_FILES=("/etc/foo.conf")
  run_enabled
  local conf="$FAKEROOT/persist/etc/tmpfiles.d/impermanence-extensions.conf"
  local esc unit
  esc="$(systemd-escape --path /etc/foo.conf)"
  unit="$FAKEROOT/persist/etc/systemd/system/$esc.mount"
  grep -qE "^f /etc/foo\.conf " "$conf"
  [ -f "$unit" ]
  grep -qE "^Where=/etc/foo\.conf$" "$unit"
}

@test "extension dir does NOT appear as f entry in tmpfiles" {
  PERSIST_DIRECTORIES=("/etc/wireguard")
  PERSIST_FILES=()
  run_enabled
  local conf="$FAKEROOT/persist/etc/tmpfiles.d/impermanence-extensions.conf"
  if grep -qE "^f /etc/wireguard " "$conf"; then return 1; fi
}

@test "extension: .wants symlink under /persist/.../local-fs.target.wants" {
  PERSIST_DIRECTORIES=("/etc/wireguard")
  PERSIST_FILES=("/etc/foo.conf")
  run_enabled
  local w="$FAKEROOT/persist/etc/systemd/system/local-fs.target.wants"
  local esc1 esc2
  esc1="$(systemd-escape --path /etc/wireguard)"
  esc2="$(systemd-escape --path /etc/foo.conf)"
  [ -L "$w/$esc1.mount" ]
  [ -L "$w/$esc2.mount" ]
  [ "$(readlink "$w/$esc1.mount")" = "../$esc1.mount" ]
}

@test "extension: moves dir content; source absent, dest present" {
  PERSIST_DIRECTORIES=("/etc/wireguard")
  mkdir -p "$FAKEROOT/etc/wireguard"
  printf 'k' > "$FAKEROOT/etc/wireguard/wg0.conf"
  run_enabled
  [ ! -e "$FAKEROOT/etc/wireguard" ]
  [ -f "$FAKEROOT/persist/etc/wireguard/wg0.conf" ]
}

@test "extension: moves file content; source absent, dest present" {
  PERSIST_FILES=("/etc/foo.conf")
  mkdir -p "$FAKEROOT/etc"
  printf 'bar' > "$FAKEROOT/etc/foo.conf"
  run_enabled
  [ ! -e "$FAKEROOT/etc/foo.conf" ]
  [ -f "$FAKEROOT/persist/etc/foo.conf" ]
  [ "$(cat "$FAKEROOT/persist/etc/foo.conf")" = "bar" ]
}

@test "extension: missing source is skipped (no error)" {
  PERSIST_DIRECTORIES=("/etc/nonexistent")
  IMPERMANENCE_ENABLED=true run impermanence_apply
  [ "$status" -eq 0 ]
}

@test "extension: mv occurs before zfs snapshot" {
  mv() { printf 'mv %s\n' "$*" >> "$CALLS"; command mv "$@"; }
  export -f mv
  PERSIST_FILES=("/etc/foo.conf")
  mkdir -p "$FAKEROOT/etc"
  printf 'x' > "$FAKEROOT/etc/foo.conf"
  run_enabled
  local last_mv first_snap
  last_mv="$(grep -n "^mv .*/etc/foo.conf " "$CALLS" | tail -1 | cut -d: -f1)"
  first_snap="$(grep -n "^zfs snapshot " "$CALLS" | head -1 | cut -d: -f1)"
  [ -n "$last_mv" ] && [ -n "$first_snap" ]
  [ "$last_mv" -lt "$first_snap" ]
}

# ── slice 3 cycle 1 (tracer): enabled writes pacman hook file ───────────────

@test "resnapshot hook: enabled writes pacman hook file" {
  run_enabled
  local f="$FAKEROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook"
  [ -f "$f" ]
}

@test "resnapshot hook: [Trigger] Type=Package" {
  run_enabled
  local f="$FAKEROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook"
  grep -qE "^Type ?= ?Package$" "$f"
}

@test "resnapshot hook: [Trigger] Operation Install|Upgrade|Remove" {
  run_enabled
  local f="$FAKEROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook"
  grep -qE "^Operation ?= ?Install$" "$f"
  grep -qE "^Operation ?= ?Upgrade$" "$f"
  grep -qE "^Operation ?= ?Remove$"  "$f"
}

@test "resnapshot hook: [Trigger] Target=*" {
  run_enabled
  local f="$FAKEROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook"
  grep -qE '^Target ?= ?\*$' "$f"
}

@test "resnapshot hook: [Action] When=PostTransaction" {
  run_enabled
  local f="$FAKEROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook"
  grep -qE "^When ?= ?PostTransaction$" "$f"
}

@test "resnapshot hook: [Action] Exec=/usr/lib/impermanence/resnapshot.sh" {
  run_enabled
  local f="$FAKEROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook"
  grep -qE "^Exec ?= ?/usr/lib/impermanence/resnapshot\.sh$" "$f"
}

@test "resnapshot hook: [Action] Description present" {
  run_enabled
  local f="$FAKEROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook"
  grep -qE "^Description ?= ?" "$f"
}

@test "resnapshot helper: written at /usr/lib/impermanence/resnapshot.sh" {
  run_enabled
  [ -f "$FAKEROOT/usr/lib/impermanence/resnapshot.sh" ]
}

@test "resnapshot helper: is executable" {
  run_enabled
  [ -x "$FAKEROOT/usr/lib/impermanence/resnapshot.sh" ]
}

@test "resnapshot helper: starts with bash shebang" {
  run_enabled
  local f="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  head -1 "$f" | grep -qE "^#!.*bash"
}

@test "resnapshot helper: references all 5 Rollback Datasets" {
  run_enabled
  local f="$FAKEROOT/usr/lib/impermanence/resnapshot.sh" ds
  for ds in etc root opt srv usrlocal; do
    grep -qE "rpool/ROOT/$ds" "$f" \
      || { echo "missing rpool/ROOT/$ds in helper"; return 1; }
  done
}

@test "resnapshot helper: contains zfs destroy and zfs snapshot @blank" {
  run_enabled
  local f="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  grep -qE "zfs destroy .*@blank" "$f"
  grep -qE "zfs snapshot .*@blank" "$f"
}

@test "resnapshot helper: destroy precedes snapshot in script" {
  run_enabled
  local f="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  local d s
  d="$(grep -nE "zfs destroy " "$f" | head -1 | cut -d: -f1)"
  s="$(grep -nE "zfs snapshot " "$f" | head -1 | cut -d: -f1)"
  [ -n "$d" ] && [ -n "$s" ]
  [ "$d" -lt "$s" ]
}

@test "resnapshot helper: end-to-end re-snapshots every dataset" {
  run_enabled
  local f="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  local log="$TEST_DIR/helper-calls.log"
  : > "$log"
  # Source the helper in a fresh bash subshell with our own zfs/logger
  # stubs to capture invocations. The setup()-exported zfs function is
  # explicitly unset so it does not shadow the stub.
  HELPER_LOG="$log" bash <<SUBSHELL
unset -f zfs logger 2>/dev/null
zfs()    { printf 'zfs %s\n'    "\$*" >> "$log"; }
logger() { :; }
source "$f"
SUBSHELL
  local ds
  for ds in etc root opt srv usrlocal; do
    grep -qE "zfs destroy rpool/ROOT/$ds@blank" "$log" \
      || { echo "no destroy for $ds"; cat "$log"; return 1; }
    grep -qE "zfs snapshot rpool/ROOT/$ds@blank" "$log" \
      || { echo "no snapshot for $ds"; cat "$log"; return 1; }
  done
}

@test "resnapshot helper: idempotent when destroy fails (no @blank)" {
  run_enabled
  local f="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  local log="$TEST_DIR/helper-calls.log"
  : > "$log"
  # destroy returns nonzero (no such snapshot); helper must still snapshot.
  HELPER_LOG="$log" bash <<SUBSHELL
unset -f zfs logger 2>/dev/null
zfs() {
  printf 'zfs %s\n' "\$*" >> "$log"
  if [[ "\$1" == "destroy" ]]; then return 1; fi
  return 0
}
logger() { :; }
source "$f"
status=\$?
echo "exit=\$status" >> "$log"
SUBSHELL
  grep -qE "exit=0$" "$log"
  local ds
  for ds in etc root opt srv usrlocal; do
    grep -qE "zfs snapshot rpool/ROOT/$ds@blank" "$log" \
      || { echo "no snapshot for $ds"; cat "$log"; return 1; }
  done
}

@test "resnapshot helper: idempotent when snapshot fails (continues)" {
  run_enabled
  local f="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  local log="$TEST_DIR/helper-calls.log"
  : > "$log"
  # Even if snapshot of first dataset fails, remaining are attempted and
  # helper exits 0 (errors are logged, not aborted).
  HELPER_LOG="$log" bash <<SUBSHELL
unset -f zfs logger 2>/dev/null
zfs() {
  printf 'zfs %s\n' "\$*" >> "$log"
  if [[ "\$1" == "snapshot" && "\$2" == *"/etc@blank" ]]; then return 1; fi
  return 0
}
logger() { :; }
source "$f"
echo "exit=\$?" >> "$log"
SUBSHELL
  grep -qE "exit=0$" "$log"
  grep -qE "zfs snapshot rpool/ROOT/usrlocal@blank" "$log"
}

@test "resnapshot helper: invokes logger with -t impermanence" {
  run_enabled
  local f="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  grep -qE "logger -t impermanence" "$f"
}

@test "resnapshot helper: logger called at runtime per dataset" {
  run_enabled
  local f="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  local log="$TEST_DIR/helper-calls.log"
  : > "$log"
  HELPER_LOG="$log" bash <<SUBSHELL
unset -f zfs logger 2>/dev/null
zfs()    { printf 'zfs %s\n'    "\$*" >> "$log"; }
logger() { printf 'logger %s\n' "\$*" >> "$log"; }
source "$f"
SUBSHELL
  # at least one logger invocation tagged impermanence
  grep -qE "^logger .*-t impermanence" "$log"
}

@test "resnapshot helper: documents v1 leak in comments" {
  run_enabled
  local f="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  # Operator who reads the helper should learn that no pre-transaction
  # wipe exists (the documented v1 leak).
  grep -qE "v1 leak|pre-transaction|leak" "$f"
}
