#!/usr/bin/env bats
# Tests for lib/boot/update-snapshot.sh — the Update Snapshot planner
# (ADR 0166).
#
# Sourced lib-only (UPDATE_SNAPSHOT_LIB_ONLY=1). Every planner reads `zfs list`
# style lines on stdin, so no pool is needed.

setup() {
  UPDATE_SNAPSHOT_LIB_ONLY=1
  # shellcheck source=../../lib/boot/update-snapshot.sh
  source "$BATS_TEST_DIRNAME/../../lib/boot/update-snapshot.sh"
}

@test "name: UTC timestamp, sorts in creation order" {
  [ "$(update_snapshot_name 0)" = update-19700101T000000 ]
  [ "$(update_snapshot_name 1793900000)" = update-20261105T173320 ]
}

@test "targets: the root dataset and the pool's /var, nothing else" {
  run update_snapshot_targets rpool/ROOT/arch <<'EOF2'
rpool
rpool/ROOT
rpool/ROOT/arch
rpool/ROOT/etc
rpool/home
rpool/tmp
rpool/var
rpool/var/cache
rpool/var/log
dpool/data
EOF2
  [ "$status" -eq 0 ]
  [ "$output" = $'rpool/ROOT/arch\nrpool/var' ]
}

@test "targets: a pool without a /var dataset snapshots the root only" {
  run update_snapshot_targets tank/ROOT/arch <<<$'tank\ntank/ROOT/arch'
  [ "$output" = tank/ROOT/arch ]
}

@test "prune: keeps the newest three Update Snapshots on every dataset" {
  run update_snapshot_prune 3 "" <<'EOF2'
rpool/ROOT/arch@update-20261101T000000
rpool/ROOT/arch@update-20261102T000000
rpool/ROOT/arch@update-20261103T000000
rpool/ROOT/arch@update-20261104T000000
rpool/var@update-20261101T000000
rpool/var@update-20261104T000000
rpool/ROOT/etc@update-20261101T000000
rpool/ROOT/etc@blank
rpool/ROOT/arch@manual
EOF2
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' \
    rpool/ROOT/arch@update-20261101T000000 \
    rpool/ROOT/etc@update-20261101T000000 \
    rpool/var@update-20261101T000000)" ]
}

@test "prune: the snapshot before an unfinished update is never pruned" {
  run update_snapshot_prune 3 update-20261101T000000 <<'EOF2'
rpool/ROOT/arch@update-20261101T000000
rpool/ROOT/arch@update-20261102T000000
rpool/ROOT/arch@update-20261103T000000
rpool/ROOT/arch@update-20261104T000000
rpool/ROOT/arch@update-20261105T000000
EOF2
  [ "$output" = rpool/ROOT/arch@update-20261102T000000 ]
}

@test "newest: the latest Update Snapshot name, empty when none" {
  run update_snapshot_newest <<'EOF2'
rpool/ROOT/arch@update-20261102T000000
rpool/ROOT/arch@blank
rpool/ROOT/arch@update-20261104T000000
EOF2
  [ "$output" = update-20261104T000000 ]
  run update_snapshot_newest <<<'rpool/ROOT/arch@blank'
  [ -z "$output" ]
}

@test "hooks: pre runs before every transaction, post after it" {
  run update_snapshot_pre_hook
  [[ "$output" == *"Type = Package"* && "$output" == *"Target = *"* ]]
  [[ "$output" == *"When = PreTransaction"* ]]
  [[ "$output" == *"update-snapshot.sh pre"* ]]
  [[ "$output" != *AbortOnFail* ]]
  run update_snapshot_post_hook
  [[ "$output" == *"When = PostTransaction"* ]]
  [[ "$output" == *"update-snapshot.sh post"* ]]
}

@test "install: snapshot after the aborting guards, before any removal" {
  local root hooks
  root="$(mktemp -d)"; hooks="$root/etc/pacman.d/hooks"
  mkdir -p "$hooks"
  : >"$hooks/00-update-snapshot.hook"
  update_snapshot_install "$root" \
    "$BATS_TEST_DIRNAME/../../lib/boot/update-snapshot.sh"
  [ -x "$root/usr/local/lib/archzfs/update-snapshot.sh" ]
  grep -q "update-snapshot.sh pre" "$hooks/02-update-snapshot.hook"
  grep -q "update-snapshot.sh post" "$hooks/zzz-update-snapshot-done.hook"
  [ ! -e "$hooks/00-update-snapshot.hook" ]
  # a guard refusing the update must not leave the in-progress mark
  [[ "01-esp-kernel-sync-preflight.hook" < "02-update-snapshot.hook" ]]
  [[ "02-update-snapshot.hook" < "60-mkinitcpio-remove.hook" ]]
  rm -rf "$root"
}

@test "keep_blank_lines: the resnapshot-loop lines calling keep-blank" {
  run update_snapshot_keep_blank_lines
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[2]}" == *'update-snapshot.sh keep-blank "${ds}"' ]]
  bash -n <(printf 'for ds in x; do\n%s\ndone\n' "$output")
}
