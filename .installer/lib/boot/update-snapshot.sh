#!/usr/bin/env bash
# =============================================================================
# lib/boot/update-snapshot.sh — Update Snapshot (ADR 0166)
# =============================================================================
# Before every pacman transaction on a ZFS root, snapshot the datasets pacman
# changes — the root and the pool's /var — as @update-<UTC time>, the state
# Undo Last Update returns to. Keeps the newest three; the snapshot taken before
# an unfinished transaction is kept until a transaction completes.
#
# Impermanence: the Rollback Datasets are not snapshotted here. Their
# pre-update state is @blank, and the boot-time `zfs rollback -r @blank` would
# destroy anything newer. Instead the Pacman Resnapshot Hook calls `keep-blank`,
# renaming the old @blank to the transaction's @update-* name before taking the
# new @blank (a renamed snapshot keeps its creation time, so it survives).
#
#   pre         PreTransaction, every transaction: snapshot, prune, mark.
#   post        PostTransaction, every transaction: clear the mark.
#   keep-blank  <dataset>…: keep each @blank as the newest @update-* name.
#
# Used by: lib/chroot/bootloader-common.sh and tools/harden-boot.sh (install),
# lib/chroot/impermanence-boot-hooks.sh (keep-blank lines), pacman hooks.
#
# Installed to /usr/local/lib/archzfs/. Sourced lib-only by tests
# (UPDATE_SNAPSHOT_LIB_ONLY=1); every planner reads `zfs list` lines on stdin.
# =============================================================================

_UPDATE_SNAPSHOT_KEEP=3   # Update Snapshots kept, newest first
# holds the snapshot taken before a transaction still in progress
_UPDATE_SNAPSHOT_MARK=/var/lib/archzfs/update-in-progress

# update_snapshot_name <epoch> — the snapshot name for a transaction started at
# <epoch>: update-YYYYmmddTHHMMSS in UTC, so names sort in creation order.
update_snapshot_name() {
  printf 'update-%s\n' "$(date -u -d "@$1" +%Y%m%dT%H%M%S)"
}

# update_snapshot_pool <dataset> — the pool a dataset lives in (its first
# path part): rpool/ROOT/arch → rpool.
update_snapshot_pool() {
  printf '%s\n' "$1" | cut -d/ -f1
}

# update_snapshot_targets <root-dataset> — from dataset names on stdin, the
# datasets to snapshot: <root-dataset> and <pool>/var when it exists. /home,
# /tmp, /var/cache, /var/log and data pools are left out.
update_snapshot_targets() {
  local root_dataset="$1" pool dataset _rest
  pool="$(update_snapshot_pool "$root_dataset")"
  while read -r dataset _rest; do
    if [[ "$dataset" == "$root_dataset" || "$dataset" == "$pool/var" ]]; then
      printf '%s\n' "$dataset"
    fi
  done
}

# _update_snapshot_is_listed <word> <list>… — 0 when <word> is in <list>.
_update_snapshot_is_listed() {
  local word="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$word" ]] && return 0
  done
  return 1
}

# update_snapshot_prune <keep> <protected-name> — from snapshot names
# (dataset@name) on stdin, the @update-* snapshots to destroy: every dataset's
# copy of a name outside the newest <keep> names and not <protected-name>.
# Names hold their UTC time, so sorting them sorts them by age.
update_snapshot_prune() {
  local keep="$1" protected="$2" snapshot name
  local -a snapshots=() names=() kept=()
  # The @update-* snapshots, sorted.
  mapfile -t snapshots < <(grep '@update-' | sort)
  (( ${#snapshots[@]} )) || return 0
  # Every distinct name, oldest first, and the newest <keep> of them.
  mapfile -t names < <(printf '%s\n' "${snapshots[@]}" | cut -d@ -f2 | sort -u)
  mapfile -t kept < <(printf '%s\n' "${names[@]}" | tail -n "$keep")
  for snapshot in "${snapshots[@]}"; do
    name="$(printf '%s\n' "$snapshot" | cut -d@ -f2)"
    [[ "$name" == "$protected" ]] && continue
    _update_snapshot_is_listed "$name" "${kept[@]}" && continue
    printf '%s\n' "$snapshot"
  done
}

# update_snapshot_newest — the newest @update-* name among the snapshot names
# on stdin; empty when there is none.
update_snapshot_newest() {
  local names
  # The @update-* names (after the "@"), oldest first.
  names="$(grep '@update-' | cut -d@ -f2 | sort)" || true
  [[ -n "$names" ]] || return 0
  printf '%s\n' "$names" | tail -n 1
}

# update_snapshot_pre_hook / update_snapshot_post_hook — the pacman hooks around
# every transaction. Single source for the installer and the retrofit. Never
# AbortOnFail: a failed snapshot warns, it does not block an update.
update_snapshot_pre_hook() {
  cat <<'HOOK'
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Operation = Remove
Target = *

[Action]
Description = Taking the Update Snapshot...
When = PreTransaction
Exec = /usr/local/lib/archzfs/update-snapshot.sh pre
HOOK
}

update_snapshot_post_hook() {
  cat <<'HOOK'
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Operation = Remove
Target = *

[Action]
Description = Marking the update complete...
When = PostTransaction
Exec = /usr/local/lib/archzfs/update-snapshot.sh post
HOOK
}

# update_snapshot_keep_blank_lines — the lines an Impermanence resnapshot
# helper runs inside its `for ds in $datasets; do` loop, before destroying
# @blank. Single source for the installer's helper and the retrofit's patch.
update_snapshot_keep_blank_lines() {
  cat <<'LINES'
  # Keep the pre-update @blank as this update's Update Snapshot (ADR 0166).
  [[ -x /usr/local/lib/archzfs/update-snapshot.sh ]] \
    && /usr/local/lib/archzfs/update-snapshot.sh keep-blank "${ds}"
LINES
}

# update_snapshot_install <root> <source-script> — install this helper and its
# hooks under <root> ("" = /). The one install path for the installer and the
# retrofit. 02- sorts after the aborting guards (00-battery, 01-esp preflight),
# so a refused update leaves no in-progress mark, and before 60-mkinitcpio-
# remove, so the snapshot holds the untouched system. The old 00- name goes.
update_snapshot_install() {
  local root="$1" source_script="$2" hooks="$1/etc/pacman.d/hooks"
  install -Dm755 "$source_script" \
    "$root/usr/local/lib/archzfs/update-snapshot.sh"
  mkdir -p "$hooks"
  rm -f "$hooks/00-update-snapshot.hook"
  update_snapshot_pre_hook >"$hooks/02-update-snapshot.hook"
  update_snapshot_post_hook >"$hooks/zzz-update-snapshot-done.hook"
}

# Lib-only sourcing for tests: skip the runtime below.
[[ "${UPDATE_SNAPSHOT_LIB_ONLY:-0}" == "1" ]] && return 0

# The dataset mounted at /, empty when the root is not ZFS.
_update_snapshot_root_dataset() {
  [[ "$(findmnt -n -o FSTYPE /)" == zfs ]] && findmnt -n -o SOURCE /
}

_update_snapshot_pre() {
  local root_dataset name protected
  local -a targets=() snapshots=() doomed=()
  local target snapshot
  root_dataset="$(_update_snapshot_root_dataset)" || return 0
  [[ -n "$root_dataset" ]] || return 0
  name="$(update_snapshot_name "$(date +%s)")"
  mapfile -t targets < <(zfs list -H -o name -t filesystem \
    | update_snapshot_targets "$root_dataset")
  for target in "${targets[@]}"; do snapshots+=("$target@$name"); done
  if ! zfs snapshot "${snapshots[@]}"; then
    echo "update-snapshot: WARN: could not take @$name — Undo Last Update" \
         "will not cover this update." >&2
    return 0
  fi
  # A mark left by an unfinished transaction protects the snapshot taken
  # before it; otherwise this transaction's snapshot is the one to protect.
  if [[ -s "$_UPDATE_SNAPSHOT_MARK" ]]; then
    protected="$(<"$_UPDATE_SNAPSHOT_MARK")"
  else
    protected="$name"
    mkdir -p "$(dirname "$_UPDATE_SNAPSHOT_MARK")"
    printf '%s\n' "$name" >"$_UPDATE_SNAPSHOT_MARK"
  fi
  # The pool's snapshots past the keep limit.
  mapfile -t doomed < <(zfs list -H -o name -t snapshot -r \
    "$(update_snapshot_pool "$root_dataset")" \
    | update_snapshot_prune "$_UPDATE_SNAPSHOT_KEEP" "$protected")
  for snapshot in "${doomed[@]}"; do zfs destroy "$snapshot"; done
  return 0
}

_update_snapshot_keep_blank() {
  local root_dataset name dataset
  root_dataset="$(_update_snapshot_root_dataset)" || return 0
  # The newest Update Snapshot of the root.
  name="$(zfs list -H -o name -t snapshot "$root_dataset" 2>/dev/null \
    | update_snapshot_newest)"
  [[ -n "$name" ]] || return 0
  for dataset in "$@"; do
    zfs list -H "$dataset@$name" >/dev/null 2>&1 && continue
    zfs rename "$dataset@blank" "$dataset@$name" 2>/dev/null || true
  done
}

case "${1:-}" in
pre) _update_snapshot_pre ;;
post) rm -f "$_UPDATE_SNAPSHOT_MARK" ;;
keep-blank)
  shift
  _update_snapshot_keep_blank "$@"
  ;;
*)
  echo "usage: update-snapshot.sh pre | post | keep-blank <dataset>…" >&2
  exit 2
  ;;
esac
