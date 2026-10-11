#!/usr/bin/env bats
# Tests: verify blocks (split from seed-generator.bats;
# shared setup in seed-generator-helpers.bash)

load seed-generator-helpers


# ── rollback firstboot block (impermanence rollback proof, ADR 0044) ──────────

@test "rollback block: boot1 writes probe to /opt + phase to /persist, reboots" {
  run _seed_generator_rollback_firstboot_block
  [ "$status" -eq 0 ]
  [[ "$output" == *": > /opt/.rollback-probe"* ]]
  [[ "$output" == *": > /persist/.rollback-phase"* ]]
  [[ "$output" == *"systemctl --no-block reboot"* ]]
}

@test "rollback block: boot2 emits the marker only when probe gone + phase survives" {
  run _seed_generator_rollback_firstboot_block
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ ! -e /opt/.rollback-probe ] && [ -e /persist/.rollback-phase ]"* ]]
  [[ "$output" == *"===FIRSTBOOT-OK==="* ]]
}

@test "rollback block: unit lives under /usr/lib (survives the @blank rollback)" {
  # /etc rolls back; the stateful unit must run on BOTH boots, so it goes in the
  # never-rolled-back root dataset (/usr/lib), not /etc.
  run _seed_generator_rollback_firstboot_block
  [ "$status" -eq 0 ]
  [[ "$output" == *"/usr/lib/systemd/system/firstboot-ok.service"* ]]
  [[ "$output" != *"/etc/systemd/system/firstboot-ok.service"* ]]
}

@test "rollback block: probe_dir override (negative control) writes to /persist" {
  run _seed_generator_rollback_firstboot_block /persist
  [ "$status" -eq 0 ]
  [[ "$output" == *": > /persist/.rollback-probe"* ]]
  [[ "$output" == *"[ ! -e /persist/.rollback-probe ]"* ]]
}

@test "rollback block: export has a forced fallback (no 'in use' panic)" {
  run _seed_generator_rollback_firstboot_block
  [ "$status" -eq 0 ]
  [[ "$output" =~ "zpool export -f rpool" ]]
}

# Hook-level fault control: break the rollback by destroying a @blank snapshot on
# boot1 so boot2's initramfs hook fails closed (missing @blank → emergency shell)
# → no marker → host RED. Proves a REAL broken rollback can't false-PASS.

@test "rollback block: break_blank destroys a @blank snapshot on boot1" {
  run _seed_generator_rollback_firstboot_block /root true
  [ "$status" -eq 0 ]
  [[ "$output" == *"zfs destroy rpool/ROOT/etc@blank"* ]]
}

@test "rollback block: default does NOT destroy any @blank snapshot" {
  run _seed_generator_rollback_firstboot_block
  [ "$status" -eq 0 ]
  [[ "$output" != *"zfs destroy"* ]]
}

# btrfs FS variant (issue 08): the rollback containers are subvolumes, so the
# fault control deletes a top-level @<name>@blank subvol instead of `zfs destroy`,
# and the seed step mounts subvol=@ (no zpool import) to drop the sentinel unit.

@test "rollback block: btrfs break deletes the @etc@blank subvol (not zfs)" {
  run _seed_generator_rollback_firstboot_block /root true btrfs
  [ "$status" -eq 0 ]
  [[ "$output" == *"btrfs subvolume delete /mnt/@etc@blank"* ]]
  [[ "$output" != *"zfs destroy"* ]]
}

@test "rollback block: btrfs default does NOT delete any @blank subvol" {
  run _seed_generator_rollback_firstboot_block /root false btrfs
  [ "$status" -eq 0 ]
  [[ "$output" != *"btrfs subvolume delete"* ]]
}

@test "rollback block: btrfs seeds the unit via subvol=@ mount, no zpool import" {
  run _seed_generator_rollback_firstboot_block /root false btrfs
  [ "$status" -eq 0 ]
  [[ "$output" == *"subvol=@ /dev/disk/by-partlabel/root /mnt"* ]]
  [[ "$output" == *"/usr/lib/systemd/system/firstboot-ok.service"* ]]
  [[ "$output" != *"zpool import"* ]]
}

@test "rollback block: zfs (default fs) still mounts via zpool import" {
  run _seed_generator_rollback_firstboot_block /root false
  [ "$status" -eq 0 ]
  [[ "$output" == *"zpool import -f -N -R /mnt rpool"* ]]
  [[ "$output" != *"btrfs subvolume delete"* ]]
}

@test "rollback block: btrfs seed scans devices before mounting (raid assembly)" {
  # On a multi-device btrfs raid the live ISO must register every member before
  # the subvol=@ mount; a `btrfs device scan` is a no-op on single disk.
  run _seed_generator_rollback_firstboot_block /root false btrfs
  [ "$status" -eq 0 ]
  [[ "$output" == *"btrfs device scan"* ]]
  # scan precedes the seed mount
  local scan_position mount_position
  scan_position="$(awk '/btrfs device scan/{print NR; exit}' <<<"$output")"
  mount_position="$(awk '/subvol=@ \/dev\/disk\/by-partlabel\/root \/mnt/{print NR; exit}' <<<"$output")"
  [ -n "$scan_position" ] && [ -n "$mount_position" ] && [ "$scan_position" -lt "$mount_position" ]
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
    run vm_seed_generator_build "$REPO_URL" "$HOSTNAME_FIXTURE" "$OUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "cloud-localds not found" ]]
}


# ── empty inputs are rejected ────────────────────────────────────────────────

@test "empty repo URL: returns non-zero" {
  run vm_seed_generator_build "" "$HOSTNAME_FIXTURE" "$OUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "REPO_URL is empty" ]]
}

@test "empty hostname: returns non-zero" {
  run vm_seed_generator_build "$REPO_URL" "" "$OUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "HOSTNAME is empty" ]]
}

@test "missing output dir: returns non-zero" {
  run vm_seed_generator_build "$REPO_URL" "$HOSTNAME_FIXTURE" "$TEST_DIR/nope"
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


# ── AUR audit boot check (ADR 0143) ─────────────────────────────────────────
# verify.aur_audit makes the first-boot sentinel run `aur-vet audit` on the
# installed system and echo ===AUR-AUDIT-OK=== / ===AUR-AUDIT-FAIL===.

@test "firstboot block: aur_audit on injects the aur-vet audit check" {
  run _seed_generator_firstboot_block "" "" "" "" true
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/usr/local/bin/aur-vet audit" ]]
  [[ "$output" =~ "===AUR-AUDIT-OK===" ]]
  [[ "$output" =~ "===AUR-AUDIT-FAIL===" ]]
}

@test "firstboot block: aur_audit off (default) omits the audit check" {
  run _seed_generator_firstboot_block ""
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "aur-vet" ]]
}


# ── wlroots polkit/idle probe markers (ADR 0100, recorded not asserted) ─────

@test "probe markers: extracts wlroots POLKIT/IDLE lines from a boot log" {
  local log="$BATS_TEST_TMPDIR/boot.log"
  printf '%s\n' 'noise' '===NIRI-SESSION-OK===' \
    '===NIRI-POLKIT-OK agents=noctalia===' '===NIRI-IDLE-OK===' \
    '[  3.1] kernel: ===HYPR-POLKIT-FAIL=== trailing' '===HYPR-IDLE-FAIL===' \
    > "$log"
  run _seed_generator_probe_markers "$log"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "===NIRI-POLKIT-OK agents=noctalia===" ]
  [ "${lines[1]}" = "===NIRI-IDLE-OK===" ]
  [ "${lines[2]}" = "===HYPR-POLKIT-FAIL===" ]
  [ "${lines[3]}" = "===HYPR-IDLE-FAIL===" ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "probe markers: extracts CLIPBOARD lines with their fields (ADR 0147)" {
  local log="$BATS_TEST_TMPDIR/boot.log"
  printf '%s\n' '===NIRI-CLIPBOARD-OK===' '===HYPR-CLIPBOARD-OK keep=xfail===' \
    '===HYPR-CLIPBOARD-FAIL live=ok primary=ok keep=fail===' > "$log"
  run _seed_generator_probe_markers "$log"
  [ "${lines[0]}" = "===NIRI-CLIPBOARD-OK===" ]
  [ "${lines[1]}" = "===HYPR-CLIPBOARD-OK keep=xfail===" ]
  [ "${lines[2]}" = "===HYPR-CLIPBOARD-FAIL live=ok primary=ok keep=fail===" ]
  [ "${#lines[@]}" -eq 3 ]
}


# ── guided manual partitioning case (ADR 0073) ──────────────────────────────

@test "guided manual: scripts a labelled table, then replays manual_disk" {
  run _seed_generator_render_guided_user_data "https://x/repo.git" vm-manual \
    false true false false single 1 "" "" false true
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sgdisk --zap-all" ]]
  [[ "$output" =~ "-t1:ef00" ]]
  [[ "$output" =~ "-t2:8200" ]]
  [[ "$output" =~ "-c3:root" ]]
  [[ "$output" =~ "udevadm settle" ]]
  [[ "$output" =~ "manual_disk=" ]]
  [[ ! "$output" =~ "\\ndisk=" ]]
}


# ── harness env passthrough (Audit Cache, ADR 0152) ─────────────────────────

@test "env exports: VM_INSTALL_ENV becomes plain or chained exports" {
  VM_INSTALL_ENV="INSTALL_PKG_CACHE_KEEP=1 INSTALL_AUDIT_AUR_URL=http://g/a"
  run _seed_generator_env_exports plain
  [ "${lines[0]}" = "export INSTALL_PKG_CACHE_KEEP='1'" ]
  [ "${lines[1]}" = "export INSTALL_AUDIT_AUR_URL='http://g/a'" ]
  run _seed_generator_env_exports chain
  local want=" && export INSTALL_PKG_CACHE_KEEP='1'"
  want+=" && export INSTALL_AUDIT_AUR_URL='http://g/a'"
  [ "$output" = "$want" ]
}

@test "env exports: empty VM_INSTALL_ENV emits nothing" {
  VM_INSTALL_ENV=""
  run _seed_generator_env_exports chain
  [ -z "$output" ]
}
