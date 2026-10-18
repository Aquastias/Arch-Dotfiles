#!/usr/bin/env bats
# Probe Gate (ADR 0152): the Host Profile conditions a probe check needs. On a
# variant lacking them the check is SKIPped with a reason — never PASS, never
# FAIL. Check-level gates live in the guest probe lib; the program-level gate
# (unselected programs' probes never run) is host-side in gate.sh.

setup() {
  INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$INSTALLER_DIR/lib/feature-audit/probe-lib.sh"
  source "$INSTALLER_DIR/lib/feature-audit/gate.sh"
  export FA_CONFIG="$BATS_TEST_TMPDIR/config.json"
}

write_variant_config() { printf '%s\n' "$1" > "$FA_CONFIG"; }

# ── check-level gates (probe lib) ───────────────────────────────────────────

@test "feature_audit_gate: unmet condition prints SKIP with reason, returns 1" {
  run feature_audit_gate xdg-dirs "needs xdg-user-dirs" false
  [ "$status" -eq 1 ]
  [ "$output" = "SKIP xdg-dirs needs xdg-user-dirs" ]
}

@test "feature_audit_gate: met condition is silent, returns 0" {
  run feature_audit_gate xdg-dirs "needs xdg-user-dirs" true
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "feature_audit_stock: true only on a stock environment" {
  write_variant_config '{"environment":{"desktop":["hyprland"],"stock":true}}'
  run feature_audit_stock; [ "$status" -eq 0 ]
  write_variant_config \
    '{"environment":{"desktop":["hyprland"],"wayland_shell":"noctalia"}}'
  run feature_audit_stock; [ "$status" -ne 0 ]
}

@test "feature_audit_has_shell: noctalia or absent (default) yes; none or stock no" {
  write_variant_config '{"environment":{"wayland_shell":"noctalia"}}'
  run feature_audit_has_shell; [ "$status" -eq 0 ]
  write_variant_config '{"environment":{}}'
  run feature_audit_has_shell; [ "$status" -eq 0 ]
  write_variant_config '{"environment":{"wayland_shell":"none"}}'
  run feature_audit_has_shell; [ "$status" -ne 0 ]
  write_variant_config '{"environment":{"stock":true}}'
  run feature_audit_has_shell; [ "$status" -ne 0 ]
}

# ── program-level gate (host) ───────────────────────────────────────────────

@test "feature_audit_probe_gate_split: unselected program's probe is skipped" {
  run feature_audit_probe_gate_split $'kitty\nnvim' \
    /x/programs/system/kitty /x/programs/security/apparmor
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = $'run\t/x/programs/system/kitty' ]
  [ "${lines[1]}" = $'skip\tapparmor' ]
}

@test "feature_audit_selected_programs: host, user and post-install programs" {
  local config
  config='{"host_programs":["smartmontools"],"users":[],
      "post_install":{"security":{"apparmor":true}}}'
  run feature_audit_selected_programs "$config"
  [ "$status" -eq 0 ]
  [[ "$output" == *smartmontools* ]]
  [[ "$output" == *apparmor* ]]
  config='{"host_programs":[],"users":[],
      "post_install":{"security":{"apparmor":false}}}'
  run feature_audit_selected_programs "$config"
  [[ "$output" != *apparmor* ]]
}

@test "feature_audit_selected_programs: no zfs-auto-snapshot without ZFS" {
  local config='{"host_programs":[],"users":[],"filesystem":"ext4",
      "post_install":{"backup":{"zfs_auto_snapshot":true,"borg":true}}}'
  run feature_audit_selected_programs "$config"
  [ "$status" -eq 0 ]
  [[ "$output" == *borg* ]]
  [[ "$output" != *zfs-auto-snapshot* ]]
}

@test "feature_audit_selected_programs: a zfs storage group keeps snapshots" {
  local config='{"host_programs":[],"users":[],"filesystem":"ext4",
      "storage_groups":[{"name":"bulk","filesystem":"zfs"}],
      "post_install":{"backup":{"zfs_auto_snapshot":true}}}'
  run feature_audit_selected_programs "$config"
  [ "$status" -eq 0 ]
  [[ "$output" == *zfs-auto-snapshot* ]]
}

# ── bind gate (host) ────────────────────────────────────────────────────────

@test "feature_audit_bind_gate: stock install skips every bind source" {
  run feature_audit_bind_gate kde '{"environment":{"desktop":["kde"],"stock":true}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *stock* ]]
}

@test "feature_audit_bind_gate: no shell skips niri/Hyprland, not KDE" {
  local config='{"environment":{"wayland_shell":"none","stock":false}}'
  run feature_audit_bind_gate niri "$config";     [ "$status" -eq 0 ]
  run feature_audit_bind_gate hyprland "$config"; [ "$status" -eq 0 ]
  run feature_audit_bind_gate kde "$config";      [ "$status" -ne 0 ]; [ -z "$output" ]
}

@test "feature_audit_bind_gate: curated base with a shell runs every session" {
  local config='{"environment":{"wayland_shell":"noctalia","stock":false}}'
  run feature_audit_bind_gate niri "$config"; [ "$status" -ne 0 ]; [ -z "$output" ]
}

# ── stderr judging ──────────────────────────────────────────────────────────

@test "feature_audit_no_stderr_but: only lines matching the ERE are tolerated" {
  run feature_audit_no_stderr_but 'Notify:' sh -c 'echo "glfw Notify: no server" >&2'
  [ "$status" -eq 0 ]
  run feature_audit_no_stderr_but 'Notify:' \
    sh -c 'echo "glfw Notify: x" >&2; echo "bad config key" >&2'
  [ "$status" -eq 1 ]
  [ "$output" = "bad config key" ]
}

@test "feature_audit_no_stderr_but: a failing command still fails" {
  run feature_audit_no_stderr_but 'Notify:' false
  [ "$status" -eq 1 ]
}

# ── Fleet gate (ADR 0157) ───────────────────────────────────────────────────

@test "feature_audit_fleet: true unless the run stamps a non-fleet host" {
  write_variant_config '{}'
  feature_audit_fleet
  write_variant_config '{"_audit":{"fleet":true}}'
  feature_audit_fleet
  write_variant_config '{"_audit":{"fleet":false}}'
  feature_audit_fleet && return 1
  return 0
}

@test "feature_audit_variant_fleet: the base is a fleet host, pure hosts not" {
  source "$INSTALLER_DIR/lib/jsonc.sh"
  source "$INSTALLER_DIR/lib/feature-audit/manifest.sh"
  [ "$(feature_audit_variant_fleet kde-pure)" = false ]
  [ "$(feature_audit_variant_fleet base)" = true ]
}
