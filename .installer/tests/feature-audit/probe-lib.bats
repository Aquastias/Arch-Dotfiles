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

cfg() { printf '%s\n' "$1" > "$FA_CONFIG"; }

# ── check-level gates (probe lib) ───────────────────────────────────────────

@test "fa_gate: unmet condition prints SKIP with reason, returns 1" {
  run fa_gate xdg-dirs "needs xdg-user-dirs" false
  [ "$status" -eq 1 ]
  [ "$output" = "SKIP xdg-dirs needs xdg-user-dirs" ]
}

@test "fa_gate: met condition is silent, returns 0" {
  run fa_gate xdg-dirs "needs xdg-user-dirs" true
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fa_stock: true only on a stock environment" {
  cfg '{"environment":{"desktop":["hyprland"],"stock":true}}'
  run fa_stock; [ "$status" -eq 0 ]
  cfg '{"environment":{"desktop":["hyprland"],"wayland_shell":"noctalia"}}'
  run fa_stock; [ "$status" -ne 0 ]
}

@test "fa_has_shell: noctalia or absent (default) yes; none or stock no" {
  cfg '{"environment":{"wayland_shell":"noctalia"}}'
  run fa_has_shell; [ "$status" -eq 0 ]
  cfg '{"environment":{}}'
  run fa_has_shell; [ "$status" -eq 0 ]
  cfg '{"environment":{"wayland_shell":"none"}}'
  run fa_has_shell; [ "$status" -ne 0 ]
  cfg '{"environment":{"stock":true}}'
  run fa_has_shell; [ "$status" -ne 0 ]
}

# ── program-level gate (host) ───────────────────────────────────────────────

@test "fa_probe_gate_split: unselected program's probe is skipped" {
  run fa_probe_gate_split $'kitty\nnvim' \
    /x/programs/system/kitty /x/programs/security/apparmor
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = $'run\t/x/programs/system/kitty' ]
  [ "${lines[1]}" = $'skip\tapparmor' ]
}

@test "fa_selected_programs: host, user and post-install programs" {
  local c
  c='{"host_programs":["smartmontools"],"users":[],
      "post_install":{"security":{"apparmor":true}}}'
  run fa_selected_programs "$c"
  [ "$status" -eq 0 ]
  [[ "$output" == *smartmontools* ]]
  [[ "$output" == *apparmor* ]]
  c='{"host_programs":[],"users":[],
      "post_install":{"security":{"apparmor":false}}}'
  run fa_selected_programs "$c"
  [[ "$output" != *apparmor* ]]
}

# ── bind gate (host) ────────────────────────────────────────────────────────

@test "fa_bind_gate: stock install skips every bind source" {
  run fa_bind_gate kde '{"environment":{"desktop":["kde"],"stock":true}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *stock* ]]
}

@test "fa_bind_gate: no shell skips niri/Hyprland, not KDE" {
  local c='{"environment":{"wayland_shell":"none"}}'
  run fa_bind_gate niri "$c";     [ "$status" -eq 0 ]
  run fa_bind_gate hyprland "$c"; [ "$status" -eq 0 ]
  run fa_bind_gate kde "$c";      [ "$status" -ne 0 ]; [ -z "$output" ]
}

@test "fa_bind_gate: curated base with a shell runs every session" {
  local c='{"environment":{"wayland_shell":"noctalia"}}'
  run fa_bind_gate niri "$c"; [ "$status" -ne 0 ]; [ -z "$output" ]
}

# ── stderr judging ──────────────────────────────────────────────────────────

@test "fa_no_stderr_but: only lines matching the ERE are tolerated" {
  run fa_no_stderr_but 'Notify:' sh -c 'echo "glfw Notify: no server" >&2'
  [ "$status" -eq 0 ]
  run fa_no_stderr_but 'Notify:' \
    sh -c 'echo "glfw Notify: x" >&2; echo "bad config key" >&2'
  [ "$status" -eq 1 ]
  [ "$output" = "bad config key" ]
}

@test "fa_no_stderr_but: a failing command still fails" {
  run fa_no_stderr_but 'Notify:' false
  [ "$status" -eq 1 ]
}

# ── Host Core gate ──────────────────────────────────────────────────────────

@test "fa_host_core: true unless the variant opts out of Host Core" {
  cfg '{}'
  fa_host_core
  cfg '{"_audit":{"host_core":true}}'
  fa_host_core
  cfg '{"_audit":{"host_core":false}}'
  ! fa_host_core
}

@test "fa_variant_host_core: pure hosts don't inherit, the base does" {
  source "$INSTALLER_DIR/lib/jsonc.sh"
  source "$INSTALLER_DIR/lib/feature-audit/manifest.sh"
  [ "$(fa_variant_host_core kde-pure)" = false ]
  [ "$(fa_variant_host_core base)" = true ]
}
