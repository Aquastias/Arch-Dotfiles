# shellcheck shell=bash
# Feature Audit probe for zfs-auto-snapshot (ADR 0152; contract:
# PROGRAM_SPEC.md).
fa_require_pkg zfs-auto-snapshot zfs-auto-snapshot || return 0
fa_as_root || return 0
for t in frequent hourly daily weekly monthly; do
  fa_check "zfs-snap-timer-$t" "zfs-auto-snapshot-$t.timer enabled" \
    systemctl is-enabled --quiet "zfs-auto-snapshot-$t.timer"
done
fa_check zfs-snap-tag "zfs-snapshot-tag.service enabled" \
  systemctl is-enabled --quiet zfs-snapshot-tag.service
# The real proof: a frequent run takes a snapshot. Judged by creation time,
# not the start's exit: a timer run in the same minute already took that
# minute's name, so the manual run collides yet the snapshot is there.
_fa_zfs_snap() {
  local t0; t0=$(($(date +%s) - 60))
  systemctl start zfs-auto-snapshot-frequent.service || true
  zfs list -Hp -t snapshot -o name,creation | awk -v t0="$t0" '
    $1 ~ /@(znap|zfs-auto-snap)_.*frequent/ && $2 >= t0 { f = 1 }
    END { exit !f }'
}
fa_check zfs-snap-takes "a frequent run creates a snapshot" _fa_zfs_snap
