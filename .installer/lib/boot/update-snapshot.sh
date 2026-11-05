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
# Installed to /usr/local/lib/archzfs/. Sourced lib-only by tests
# (UPDATE_SNAPSHOT_LIB_ONLY=1); every planner reads `zfs list` lines on stdin.
# =============================================================================

_UPDATE_SNAPSHOT_KEEP=3
_UPDATE_SNAPSHOT_MARK=/var/lib/archzfs/update-in-progress

# update_snapshot_name <epoch> — the snapshot name for a transaction started at
# <epoch>: update-YYYYmmddTHHMMSS in UTC, so names sort in creation order.
update_snapshot_name() {
  printf 'update-%s\n' "$(date -u -d "@$1" +%Y%m%dT%H%M%S)"
}

# update_snapshot_targets <root-dataset> — from dataset names on stdin, the
# datasets to snapshot: <root-dataset> and <pool>/var when it exists. /home,
# /tmp, /var/cache, /var/log and data pools are left out.
update_snapshot_targets() {
  local root_dataset="$1"
  awk -v root="$root_dataset" -v var="${root_dataset%%/*}/var" \
    '$1 == root || $1 == var { print $1 }'
}

# update_snapshot_prune <keep> <protected-name> — from snapshot names
# (dataset@name) on stdin, the @update-* snapshots to destroy: every dataset's
# copy of a name outside the newest <keep> names and not <protected-name>.
update_snapshot_prune() {
  local keep="$1" protected="$2"
  awk -F@ '$2 ~ /^update-/' | sort -t@ -k2,2 -k1,1 | awk -F@ \
    -v keep="$keep" -v protected="$protected" '
      { line[NR] = $0; name[NR] = $2; if (!seen[$2]++) order[++names] = $2 }
      END {
        for (i = names - keep + 1; i <= names; i++)
          if (i > 0) kept[order[i]] = 1
        for (i = 1; i <= NR; i++)
          if (!kept[name[i]] && name[i] != protected) print line[i]
      }' | sort
}

# update_snapshot_newest — the newest @update-* name among the snapshot names
# on stdin; empty when there is none.
update_snapshot_newest() {
  awk -F@ '$2 ~ /^update-/ { print $2 }' | sort | awk 'END { if (NR) print }'
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

# Lib-only sourcing for tests: skip the runtime below.
[[ "${UPDATE_SNAPSHOT_LIB_ONLY:-0}" == "1" ]] && return 0

# The dataset mounted at /, empty when the root is not ZFS.
_update_snapshot_root_dataset() {
  [[ "$(findmnt -n -o FSTYPE /)" == zfs ]] && findmnt -n -o SOURCE /
}

_update_snapshot_pre() {
  local root_dataset name protected
  local -a targets=()
  root_dataset="$(_update_snapshot_root_dataset)" || return 0
  [[ -n "$root_dataset" ]] || return 0
  name="$(update_snapshot_name "$(date +%s)")"
  mapfile -t targets < <(zfs list -H -o name -t filesystem \
    | update_snapshot_targets "$root_dataset")
  if ! zfs snapshot "${targets[@]/%/@$name}"; then
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
    mkdir -p "${_UPDATE_SNAPSHOT_MARK%/*}"
    printf '%s\n' "$name" >"$_UPDATE_SNAPSHOT_MARK"
  fi
  zfs list -H -o name -t snapshot -r "${root_dataset%%/*}" \
    | update_snapshot_prune "$_UPDATE_SNAPSHOT_KEEP" "$protected" \
    | while IFS= read -r snapshot; do zfs destroy "$snapshot"; done
  return 0
}

_update_snapshot_keep_blank() {
  local root_dataset name dataset
  root_dataset="$(_update_snapshot_root_dataset)" || return 0
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
