# shellcheck shell=bash
# Feature Audit probe for zfs-auto-snapshot (ADR 0152; contract:
# PROGRAM_SPEC.md).
feature_audit_require_package zfs-auto-snapshot zfs-auto-snapshot || return 0
feature_audit_as_root || return 0
for timer in frequent hourly daily weekly monthly; do
  feature_audit_check "zfs-snap-timer-$timer" \
    "zfs-auto-snapshot-$timer.timer enabled" \
    systemctl is-enabled --quiet "zfs-auto-snapshot-$timer.timer"
done
feature_audit_check zfs-snap-tag "zfs-snapshot-tag.service enabled" \
  systemctl is-enabled --quiet zfs-snapshot-tag.service
# The real proof: a frequent run takes a snapshot. Judged by creation time,
# not the start's exit: the unit returns before the snapshot lands (poll),
# and a run in a minute that already has one collides on its name.
_probe_zfs_snap() {
  local since; since=$(($(date +%s) - 60))
  systemctl start zfs-auto-snapshot-frequent.service || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    zfs list -Hp -t snapshot -o name,creation | awk -v t0="$since" '
      $1 ~ /@(znap|zfs-auto-snap)_.*frequent/ && $2 >= t0 { f = 1 }
      END { exit !f }' && return 0
    sleep 2
  done
  return 1
}
feature_audit_check zfs-snap-takes \
  "a frequent run creates a snapshot" _probe_zfs_snap
