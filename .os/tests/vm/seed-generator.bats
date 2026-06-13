#!/usr/bin/env bats
# Tests for .os/lib/seed-generator.sh — cloud-init NoCloud seed-ISO builder.
#
# Strategy:
#   - Substitution + runcmd-shape tests inspect the rendered user-data text
#     directly via the _seed_generator_render_user_data seam, so they do not
#     require cloud-localds.
#   - The missing-cloud-localds test stubs PATH so cloud-localds is not
#     resolvable, then asserts seed_generator_build exits non-zero with a
#     clear message.

setup() {
  TEST_DIR="$(mktemp -d)"
  OUT_DIR="$TEST_DIR/out"
  mkdir -p "$OUT_DIR"

  REPO_URL="https://github.com/example/dotfiles.git"
  HOSTNAME_FIXTURE="vm-test-host"

  # shellcheck source=../../vm/lib/seed-generator.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/seed-generator.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── substitution: REPO_URL and HOSTNAME appear literally in user-data ────────

@test "user-data: contains literal REPO_URL with no placeholder remaining" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "$REPO_URL" ]]
  [[ ! "$output" =~ \$\{?REPO_URL\}? ]]
}

@test "user-data: contains literal HOSTNAME with no placeholder remaining" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "\"$HOSTNAME_FIXTURE\"" ]]
  [[ ! "$output" =~ \$\{?HOSTNAME\}? ]]
}

# ── runcmd shape: cloud-config header, ttyS0 redirect, sentinel, poweroff ────

@test "user-data: starts with #cloud-config header" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  first_line="$(printf '%s\n' "$output" | head -1)"
  [ "$first_line" = "#cloud-config" ]
}

@test "user-data: routes cloud-init output to /dev/ttyS0" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  # output: directive is the right hook for cloud-init's own stdio routing.
  # A bare `exec > /dev/ttyS0` line only redirects one runcmd shell.
  [[ "$output" =~ "tee -a /dev/ttyS0" ]]
  [[ "$output" =~ "output:" ]]
}

@test "user-data: runs install.sh --unattended" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "./install.sh --unattended" ]]
}

@test "user-data: emits the sentinel line in the documented format" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "===INSTALLER-EXIT-%d===" ]]
  [[ "$output" =~ "> /dev/ttyS0" ]]
}

@test "user-data: ends the runcmd with sync + poweroff" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sync" ]]
  [[ "$output" =~ "poweroff -f" ]]
}

@test "user-data: clones the repo into /root/dotfiles" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "git clone $REPO_URL /root/dotfiles" ]]
  [[ "$output" =~ "rm -rf /root/dotfiles" ]]
}

@test "user-data: patches install.jsonc hostname before running install" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sed -i" ]]
  [[ "$output" =~ "install.jsonc" ]]
}

# ── dirty-cache pre-seed (boot-verify fixture) ───────────────────────────────

@test "dirty-cache off by default: no zpool.cache garbage in user-data" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "zpool.cache" ]]
}

@test "dirty-cache on: corrupts /etc/zfs/zpool.cache before install.sh" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE" true false
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/etc/zfs/zpool.cache" ]]
  # the garbage write must be chained ahead of the installer
  pre="${output%%./install.sh*}"
  [[ "$pre" =~ "/etc/zfs/zpool.cache" ]]
}

# ── first-boot sentinel injection (boot-verify fixture) ──────────────────────

@test "verify-boot off by default: no first-boot unit in user-data" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "firstboot-ok" ]]
}

@test "verify-boot on: injects a self-disabling first-boot sentinel unit" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE" false true
  [ "$status" -eq 0 ]
  [[ "$output" =~ "firstboot-ok.service" ]]
  [[ "$output" =~ "$SEED_GENERATOR_FIRSTBOOT_MARKER" ]]
  [[ "$output" =~ "systemctl disable firstboot-ok.service" ]]
  # -N (no auto-mount) keeps the export clean — without it the busy datasets
  # leave the pool active + hostid-stamped and the next boot panics.
  [[ "$output" =~ "zpool import -f -N -R /mnt rpool" ]]
  [[ "$output" =~ "zpool export rpool" ]]
}

@test "verify-boot on: export has a forced fallback (clean export even if busy)" {
  # Regression for zfs-boot-verify/02: a plain `zpool export rpool || true`
  # swallowed a failed export, leaving the pool stamped "in use by archiso"
  # (foreign hostid). The installed initramfs then refused the import without
  # -f and PID 1 panicked. A forced-export fallback always clears the active
  # flag so the installed system imports root cleanly.
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE" false true
  [ "$status" -eq 0 ]
  [[ "$output" =~ "zpool export -f rpool" ]]
}

@test "verify-boot marker matches the shared constant contract" {
  [ "$SEED_GENERATOR_FIRSTBOOT_MARKER" = "===FIRSTBOOT-OK===" ]
}

@test "verify-boot on: first-boot unit dumps zfs-import service deps to serial" {
  # AC #1 (boot-import-strategy/01): prove the booted system's zfs-import
  # services no longer require systemd-udev-settle. The sentinel dumps their
  # resolved Requires/After to serial before the marker so the boot log
  # carries the structural proof, not just a clean boot.
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE" false true
  [ "$status" -eq 0 ]
  [[ "$output" =~ "===DIAG-ZFS-IMPORT-DEPS===" ]]
  [[ "$output" =~ "systemctl show zfs-import-cache.service zfs-import-scan.service" ]]
  [[ "$output" =~ "-p Requires" ]]
}

@test "verify-boot on: first-boot unit dumps the installed udev settle line" {
  # AC #1 (boot-import-strategy/02): prove the installed initramfs udev hook
  # carries the bounded settle. The sentinel greps the settle line out of the
  # installed override hook and prints it to serial before the marker.
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE" false true
  [ "$status" -eq 0 ]
  [[ "$output" =~ "===DIAG-UDEV-SETTLE===" ]]
  [[ "$output" =~ "/etc/initcpio/hooks/udev" ]]
  [[ "$output" =~ "settle" ]]
}

# ── multi-disk first-boot pool verifier injection (issue 06 / ADR 0027) ──────

@test "multi firstboot block: ships the verifier and bakes the expectations" {
  run _seed_generator_multi_firstboot_block "rpool tank0 tank1" \
    "tank0/data:/data/tank0 tank1/data:/data/tank1"
  [ "$status" -eq 0 ]
  # the unit-tested verifier is installed into the booted system
  [[ "$output" =~ "vm-pool-verify.sh" ]]
  # expected pools + mounts are baked in for the booted check
  [[ "$output" =~ "VM_VERIFY_POOLS=(rpool tank0 tank1)" ]]
  [[ "$output" =~ "VM_VERIFY_MOUNTS=(tank0/data:/data/tank0 tank1/data:/data/tank1)" ]]
}

@test "multi firstboot block: byid arg bakes VM_VERIFY_BYID into the env" {
  run _seed_generator_multi_firstboot_block "rpool tank0" \
    "tank0/data:/data/tank0" true
  [ "$status" -eq 0 ]
  [[ "$output" =~ "VM_VERIFY_BYID=true" ]]
}

@test "multi firstboot block: byid defaults off (no VM_VERIFY_BYID line)" {
  run _seed_generator_multi_firstboot_block "rpool tank0" \
    "tank0/data:/data/tank0"
  [ "$status" -eq 0 ]
  [[ "$output" != *"VM_VERIFY_BYID"* ]]
}

@test "multi firstboot block: owned arg bakes VM_VERIFY_OWNED into the env" {
  run _seed_generator_multi_firstboot_block "rpool tank0" \
    "tank0/data:/data/tank0" false "/data/tank0:vm-test"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "VM_VERIFY_OWNED=(/data/tank0:vm-test)" ]]
}

@test "multi firstboot block: export has a forced fallback (clean even if busy)" {
  # Same zfs-boot-verify/02 regression as the single-disk block: never leave
  # the pool stamped "in use" after the injection or the next boot panics.
  run _seed_generator_multi_firstboot_block "rpool tank0" "tank0/data:/data/tank0"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "zpool export -f rpool" ]]
}

@test "multi firstboot block: owned defaults off (no VM_VERIFY_OWNED line)" {
  run _seed_generator_multi_firstboot_block "rpool tank0" \
    "tank0/data:/data/tank0"
  [ "$status" -eq 0 ]
  [[ "$output" != *"VM_VERIFY_OWNED"* ]]
}

@test "multi firstboot block: emits the marker only via the verifier" {
  run _seed_generator_multi_firstboot_block "rpool" ""
  [ "$status" -eq 0 ]
  # the sentinel is gated on vm_pool_verify, not echoed unconditionally
  [[ "$output" =~ "vm_pool_verify" ]]
  [[ "$output" =~ "$SEED_GENERATOR_FIRSTBOOT_MARKER" ]]
  [[ "$output" =~ "firstboot-ok.service" ]]
}

@test "multi firstboot block: re-imports and exports rpool around injection" {
  run _seed_generator_multi_firstboot_block "rpool" ""
  [ "$status" -eq 0 ]
  # -N (no auto-mount) keeps the export clean — without it the busy datasets
  # leave the pool active + hostid-stamped and the next boot panics.
  [[ "$output" =~ "zpool import -f -N -R /mnt rpool" ]]
  [[ "$output" =~ "zpool export rpool" ]]
}

# ── missing cloud-localds is a clear failure (no install attempt) ────────────

@test "missing cloud-localds: returns non-zero with a clear message" {
  PATH="/this/does/not/exist" \
    run seed_generator_build "$REPO_URL" "$HOSTNAME_FIXTURE" "$OUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "cloud-localds not found" ]]
}

# ── empty inputs are rejected ────────────────────────────────────────────────

@test "empty repo URL: returns non-zero" {
  run seed_generator_build "" "$HOSTNAME_FIXTURE" "$OUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "REPO_URL is empty" ]]
}

@test "empty hostname: returns non-zero" {
  run seed_generator_build "$REPO_URL" "" "$OUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "HOSTNAME is empty" ]]
}

@test "missing output dir: returns non-zero" {
  run seed_generator_build "$REPO_URL" "$HOSTNAME_FIXTURE" "$TEST_DIR/nope"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "output directory does not exist" ]]
}

@test "esp-resilience firstboot block: ships verifier + sentinel on pass" {
  run _seed_generator_esp_resilience_firstboot_block
  [ "$status" -eq 0 ]
  [[ "$output" =~ "esp-resilience-verify.sh" ]]
  [[ "$output" =~ "esp_resilience_verify" ]]
  [[ "$output" =~ "$SEED_GENERATOR_FIRSTBOOT_MARKER" ]]
}
