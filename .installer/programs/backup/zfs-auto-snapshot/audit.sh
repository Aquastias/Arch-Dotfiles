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
# The real proof: a frequent run takes a snapshot.
_fa_zfs_snap() {
  systemctl start zfs-auto-snapshot-frequent.service \
    && zfs list -H -t snapshot -o name | grep -qE '@(znap|zfs-auto-snap)_.*frequent'
}
fa_check zfs-snap-takes "a frequent run creates a snapshot" _fa_zfs_snap
