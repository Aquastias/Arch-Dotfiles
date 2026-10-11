#!/usr/bin/env bats
# Tests: runcmd and sentinels (split from seed-generator.bats;
# shared setup in seed-generator-helpers.bash)

load seed-generator-helpers


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
  first_line="${output%%$'\n'*}"
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

@test "user-data: runs install.sh --unattended with a positional config" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  # Positional config (ADR 0039): bare install.sh now launches the Guided
  # Installer, so the seed must pass its config explicitly.
  [[ "$output" =~ "./install.sh --unattended install.jsonc" ]]
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


# ── Security & Backup Extras boot check (issue 04/05 VM smoke) ───────────────
# When the firstboot block is given a unit list, it emits ===EXTRAS-OK=== iff
# every named unit is enabled on the booted system, else ===EXTRAS-FAIL=== — a
# diagnostic prefix like USER-OK, grepped from the -boot.log.

@test "firstboot block: a verify_extras list injects an EXTRAS is-enabled check" {
  run _seed_generator_firstboot_block "" "firewalld.service apparmor.service"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "===EXTRAS-OK===" ]]
  [[ "$output" =~ "===EXTRAS-FAIL===" ]]
  # One is-enabled call over every unit (exits 0 only when all are enabled).
  [[ "$output" =~ "is-enabled firewalld.service apparmor.service" ]]
}

@test "firstboot block: no verify_extras omits the EXTRAS check" {
  run _seed_generator_firstboot_block ""
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "===EXTRAS-OK===" ]]
}


# ── per-desktop session verification (ADR 0062) ──────────────────────────────

@test "desktop marker: kde/hyprland/niri map to their OK sentinel tags" {
  [ "$(_seed_generator_desktop_marker kde)" = "===KDE-OK===" ]
  [ "$(_seed_generator_desktop_marker hyprland)" = "===HYPR-OK===" ]
  [ "$(_seed_generator_desktop_marker niri)" = "===NIRI-OK===" ]
  [ -z "$(_seed_generator_desktop_marker gnome)" ]   # unknown → empty
}

@test "desktop check: niri probes its binary + curated session file" {
  run _seed_generator_desktop_check niri
  [ "$status" -eq 0 ]
  [[ "$output" =~ "===NIRI-OK===" ]]
  [[ "$output" =~ "===NIRI-FAIL===" ]]
  [[ "$output" =~ "command -v niri" ]]
  [[ "$output" =~ "wayland-sessions/niri.desktop" ]]
  [[ "$output" != *"'"* ]]
}

@test "session file/tag: niri logs into niri.desktop with the NIRI tag" {
  [ "$(_seed_generator_session_tag niri)" = "NIRI" ]
  [ "$(_seed_generator_session_file niri)" = "niri.desktop" ]
  [ "$(_seed_generator_session_marker niri)" = "===NIRI-SESSION-OK===" ]
}

@test "desktop check: kde+hyprland emit both OK/FAIL checks, no single quotes" {
  run _seed_generator_desktop_check kde hyprland
  [ "$status" -eq 0 ]
  [[ "$output" =~ "===KDE-OK===" ]]
  [[ "$output" =~ "===KDE-FAIL===" ]]
  [[ "$output" =~ "===HYPR-OK===" ]]
  [[ "$output" =~ "===HYPR-FAIL===" ]]
  [[ "$output" =~ "startplasma-wayland" ]]           # KDE session-launch probe
  [[ "$output" =~ "wayland-sessions/hyprland.desktop" ]]  # Hyprland override
  # The whole snippet rides a single-quoted printf ExecStart arg — no ' allowed.
  [[ "$output" != *"'"* ]]
}

# The display manager is a separate axis (ADR 0069): the KDE session-artifact
# check must NOT couple to whichever greeter is enabled, or a greetd co-install
# falsely fails.
@test "desktop check: KDE probe no longer couples to 'is-enabled sddm'" {
  run _seed_generator_desktop_check kde hyprland
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "is-enabled sddm" ]]
}


# ── display manager enablement check (ADR 0069) ─────────────────────────────

@test "firstboot block: a resolved DM injects a DM is-enabled check" {
  run _seed_generator_firstboot_block "" "" "kde hyprland" "greetd"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "is-enabled greetd.service" ]]
  [[ "$output" =~ "===DM-OK===" ]]
  [[ "$output" =~ "===DM-FAIL===" ]]
}

@test "firstboot block: an sddm DM asserts sddm is enabled" {
  run _seed_generator_firstboot_block "" "" "kde" "sddm"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "is-enabled sddm.service" ]]
  [[ "$output" =~ "===DM-OK===" ]]
}

@test "firstboot block: no resolved DM omits the DM check" {
  run _seed_generator_firstboot_block "" "" "kde hyprland"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "===DM-OK===" ]]
}

@test "firstboot block: a verify_desktops list folds the per-desktop checks in" {
  run _seed_generator_firstboot_block "" "" "kde hyprland"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "===KDE-OK===" ]]
  [[ "$output" =~ "===HYPR-OK===" ]]
}

@test "firstboot block: no verify_desktops omits the per-desktop checks" {
  run _seed_generator_firstboot_block ""
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "===KDE-OK===" ]]
  [[ ! "$output" =~ "===HYPR-OK===" ]]
}


# ── per-desktop graphical-login verification (ADR 0062) ──────────────────────

@test "session marker/tag/file: kde+hyprland map consistently" {
  [ "$(_seed_generator_session_tag kde)" = "KDE" ]
  [ "$(_seed_generator_session_tag hyprland)" = "HYPR" ]
  [ "$(_seed_generator_session_file kde)" = "plasma.desktop" ]
  [ "$(_seed_generator_session_file hyprland)" = "hyprland.desktop" ]
  [ "$(_seed_generator_session_marker kde)" = "===KDE-SESSION-OK===" ]
  [ "$(_seed_generator_session_marker hyprland)" = "===HYPR-SESSION-OK===" ]
}

@test "session block: stages the prober, autologin (first session), + state" {
  run _seed_generator_session_firstboot_block aquastias kde hyprland
  [ "$status" -eq 0 ]
  # Prober + oneshot copied from the shipped fixtures, enabled at graphical.target
  [[ "$output" =~ "fixtures/desktop-verify/desktop-verify /mnt/usr/local/bin" ]]
  [[ "$output" =~ "graphical.target.wants/desktop-verify.service" ]]
  # SDDM autologin points at the FIRST desktop's session, as the named user
  [[ "$output" =~ "User=aquastias" ]]
  [[ "$output" =~ "Session=plasma.desktop" ]]
  # State the prober chains through: session order + tags, in request order
  [[ "$output" =~ "plasma.desktop hyprland.desktop" ]]
  [[ "$output" =~ "KDE HYPR" ]]
  # State MUST live on the root dataset (/usr/local), never /var — the ZFS
  # single-disk layout gives /var its own dataset that would hide it at boot.
  [[ "$output" =~ "/usr/local/lib/desktop-verify/order" ]]
  [[ ! "$output" =~ "/var/lib/desktop-verify" ]]
  # Encrypted ZFS root is imported + key-loaded to stage into it
  [[ "$output" =~ "zfs load-key -a" ]]
}

@test "session block: single desktop yields a one-entry order" {
  run _seed_generator_session_firstboot_block bob hyprland
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Session=hyprland.desktop" ]]
  [[ "$output" =~ "User=bob" ]]
}

@test "firstboot block: a btrfs root mounts subvol=@ to inject the sentinel" {
  # A btrfs root keeps the OS in subvol @ (ADR 0043, issue 07). The injector
  # must mount @ — mounting the top-level subvol by partlabel would write the
  # sentinel unit where /etc doesn't exist, so it never fires and boot-verify
  # times out. The rendered runcmd detects btrfs at guest runtime (blkid) and
  # adds subvol=@; ext4/xfs (no subvol) keep the bare partlabel mount.
  run _seed_generator_firstboot_block ""
  [ "$status" -eq 0 ]
  # runtime btrfs detection (blkid) gates the subvol=@ mount of the partlabel
  [[ "$output" =~ "blkid" ]]
  [[ "$output" =~ "= btrfs" ]]
  [[ "$output" =~ "mount -o subvol=@ /dev/disk/by-partlabel/root /mnt" ]]
}

@test "firstboot block: an encrypted (LUKS) root opens the container first" {
  # An encrypted ext4/xfs/btrfs root exposes a LUKS *container* at the 'root'
  # partlabel — mounting it raw fails, so the sentinel lands nowhere and
  # boot-verify times out (combination-matrix/07). The injector detects
  # crypto_LUKS at runtime, opens it with the test passphrase, and mounts the
  # resulting mapper (subvol=@ for btrfs). Plaintext roots skip this branch.
  run _seed_generator_firstboot_block ""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "= crypto_LUKS" ]]
  [[ "$output" =~ "cryptsetup open" ]]
  [[ "$output" =~ "/dev/mapper/cryptroot" ]]
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
