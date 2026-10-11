#!/usr/bin/env bash
# =============================================================================
# vm/lib/seed-generator-firstboot.sh — first-boot verification blocks
# =============================================================================
# The per-feature first-boot check scripts the seed generator embeds into the
# installed system (session, ESP, multi-disk, ESP resilience, rollback).
#
# Used by: vm/lib/seed-generator.sh (sources it).
# =============================================================================

# _seed_generator_session_firstboot_block <user> <de>... — the graphical-login
# verify block (ADR 0062). Mounts the freshly installed (ZFS-native-encrypted)
# root from the live ISO and stages the TEST-ONLY session prober: the shipped
# desktop-verify script + its graphical.target oneshot, an SDDM Autologin config
# pointed at the FIRST desktop's session, and the state files (order/tags/user)
# the prober chains through. On the booted guest the prober logs into each
# session in turn (self-rebooting between them) and emits
# ===<TAG>-SESSION-OK===, ending on ===SESSION-VERIFY-DONE===. The host waits
# for DONE and asserts every OK marker. ZFS-only (the KDE+Hyprland desktop
# profiles are ZFS).
_seed_generator_session_firstboot_block() {
  local user="${1:?session block needs a user}"; shift
  local -a des=("$@") sessions=() tags=() desktop
  for desktop in "${des[@]}"; do
    sessions+=("$(_seed_generator_session_file "$desktop")")
    tags+=("$(_seed_generator_session_tag "$desktop")")
  done
  local order="${sessions[*]}" tagline="${tags[*]}" first="${sessions[0]}"
  local fixtures_directory=/root/dotfiles/.installer/vm/fixtures/desktop-verify
  cat <<BLOCK
    if [ "\$rc" -eq 0 ]; then
      if zpool import -f -N -R /mnt rpool 2>/dev/null; then
        printf '%s' "\$INSTALL_ENC_PASSPHRASE" | zfs load-key -a 2>/dev/null \\
          || true
        zfs mount rpool/ROOT/arch || true
      fi
$(_seed_generator_esp_serial_lines)
      install -d /mnt/usr/local/bin /mnt/etc/sddm.conf.d \\
        /mnt/usr/local/lib/desktop-verify \\
        /mnt/etc/systemd/system/graphical.target.wants
      install -Dm755 ${fixtures_directory}/desktop-verify /mnt/usr/local/bin/desktop-verify
      install -Dm644 ${fixtures_directory}/desktop-verify.service \\
        /mnt/etc/systemd/system/desktop-verify.service
      ln -sf ../desktop-verify.service \\
        /mnt/etc/systemd/system/graphical.target.wants/desktop-verify.service
      # State on the ROOT dataset (/usr/local), NOT /var — the ZFS single-disk
      # layout puts /var on its own dataset that would mount over (hide) it.
      printf '%s\n' '${order}'   > /mnt/usr/local/lib/desktop-verify/order
      printf '%s\n' '${tagline}' > /mnt/usr/local/lib/desktop-verify/tags
      printf '%s\n' '${user}'    > /mnt/usr/local/lib/desktop-verify/user
      printf '%s\n' '0'          > /mnt/usr/local/lib/desktop-verify/idx
      printf '%s\n' '[Autologin]' 'User=${user}' 'Session=${first}' \\
        > /mnt/etc/sddm.conf.d/zz-desktop-verify.conf
      zfs umount -a || true
      zpool export rpool || zpool export -f rpool || true
    fi
BLOCK
}

# (test-only) Append a serial console to the installed kernel cmdline so the
# boot-verify phase can observe the boot. The product cmdline carries no
# console=ttyS0 (systemd-boot itself prints to serial, but once the kernel
# starts the serial goes dark), so the host sees only the boot menu then 600 s
# of silence — even the first-boot sentinel write was invisible. Add
# console=ttyS0 to BOTH bootloaders so /dev/console (kernel logs, systemd,
# emergency prompts, the LUKS/zfs unlock prompt, and the sentinel) lands on
# serial: systemd-boot's loader entries on the ESP, and GRUB's grub.cfg linux
# lines (GRUB serial parity, combination-matrix/07 — encrypted GRUB cells must
# route their unlock prompt to serial for the Console Answerer). Emitted as
# 6-space-indented runcmd lines; runs on the live ISO with the installed root
# already mounted at /mnt. Single-quoted heredoc: the inner $/$() are literal,
# evaluated on the VM, not at render time.
_seed_generator_esp_serial_lines() {
  cat <<'LINES'
      mkdir -p /mnt/boot/efi
      for _p in $(blkid -o device -t TYPE=vfat); do
        mount "$_p" /mnt/boot/efi 2>/dev/null || continue
        if [ -d /mnt/boot/efi/loader/entries ]; then
          for _e in /mnt/boot/efi/loader/entries/*.conf; do
            grep -q console=ttyS0 "$_e" \
              || sed -i '/^options /s/$/ console=ttyS0,115200/' "$_e"
          done
          umount /mnt/boot/efi; break
        fi
        umount /mnt/boot/efi
      done
      for _g in /mnt/boot/grub/grub.cfg /mnt/boot/efi/EFI/*/grub.cfg; do
        [ -f "$_g" ] || continue
        grep -q console=ttyS0 "$_g" \
          || sed -i '/^[[:space:]]*linux/s/$/ console=ttyS0,115200/' "$_g"
      done
LINES
}

# Render the post-install boot-verify injection: re-import the freshly
# installed root pool at an altroot, drop a self-disabling oneshot unit that
# echoes the boot sentinel to /dev/ttyS0, wire it into multi-user.target, then
# export. Emitted as shell lines indented to sit inside the runcmd YAML block.
# Test-only — never part of a production install.
#
# Import with -N (no auto-mount) and mount ONLY the root dataset: a plain
# `zpool import` mounts every dataset (home, var, var/log, …), which are then
# busy at `zpool export` time. The export fails, the pool stays active stamped
# with the live ISO's hostid, and the next boot panics in the initramfs ZFS
# hook ("pool was previously in use from another system"). -N keeps the export
# clean so the installed system imports root without -f. Do not drop it.
# Args: [verify_user]. When <verify_user> is set, the boot-verify sentinel also
# checks that the named user exists on the installed system with a usable
# password hash (passwd -S … P) and emits ===USER-OK=== (or ===USER-FAIL===)
# before the boot marker — the issue-07 "the user can log in" proxy. The check
# uses no single quotes (the ExecStart line is a single-quoted printf arg).
_seed_generator_firstboot_block() {
  local marker="$SEED_GENERATOR_FIRSTBOOT_MARKER" verify_user="${1:-}"
  local verify_extras="${2:-}" verify_desktops="${3:-}" \
    verify_display_manager="${4:-}"
  local verify_aur="${5:-false}"
  local user_check=""
  [[ -n "$verify_user" ]] \
    && user_check="if id ${verify_user} > /dev/null 2>&1 && passwd -S ${verify_user} 2>/dev/null | grep -qw P; then echo ===USER-OK===; else echo ===USER-FAIL===; fi; "
  # Per-desktop session-artifact check (ADR 0062): each named desktop echoes its
  # OK/FAIL marker before the boot sentinel, so the harness can assert a
  # KDE+Hyprland install produced a launchable session for each.
  local desktop_check=""
  if [[ -n "$verify_desktops" ]]; then
    local -a _des; read -ra _des <<< "$verify_desktops"
    desktop_check="$(_seed_generator_desktop_check "${_des[@]}")"
  fi
  # Security & Backup Extras check (issue 04/05): every named unit must be
  # is-enabled on the booted system. A single `systemctl is-enabled u1 u2 …`
  # exits 0 only when ALL are enabled — so one call, no loop, no single quotes
  # (the ExecStart is a single-quoted printf arg), like user_check above.
  local extras_check=""
  [[ -n "$verify_extras" ]] \
    && extras_check="if systemctl is-enabled ${verify_extras} > /dev/null 2>&1; then echo ===EXTRAS-OK===; else echo ===EXTRAS-FAIL===; fi; "
  # Display Manager check (ADR 0069): the resolved greeter — greetd or sddm — is
  # a separate axis from the desktop, so its enablement is proven on its own
  # rather than folded into the per-desktop KDE check (which now proves session
  # artifacts only). Same one-`is-enabled` shape as extras_check.
  local display_manager_check=""
  [[ -n "$verify_display_manager" ]] \
    && display_manager_check="if systemctl is-enabled ${verify_display_manager}.service > /dev/null 2>&1; then echo ===DM-OK===; else echo ===DM-FAIL===; fi; "
  # AUR Vetting audit (ADR 0143): the installed VM checks its foreign packages
  # and npm/bun caches against the Indicators. Same OK/FAIL shape as above.
  local aur_check=""
  if [[ "$verify_aur" == "true" ]]; then
    aur_check="if /usr/local/bin/aur-vet audit; then echo ===AUR-AUDIT-OK===; "
    aur_check+="else echo ===AUR-AUDIT-FAIL===; fi; "
  fi
  cat <<BLOCK
    if [ "\$rc" -eq 0 ]; then
      # Mount the freshly installed root to inject the sentinel: a ZFS root via
      # pool import, a non-ZFS (ext4/xfs/btrfs) root via its GPT partlabel
      # 'root' the Root Layout Adapter set (ADR 0043).
      if zpool import -f -N -R /mnt rpool 2>/dev/null; then
        # An encrypted root's key is NOT loaded by a bare import, so the root
        # dataset can't mount and the sentinel would land on an empty /mnt →
        # no first-boot marker at real boot (combination-matrix/07). Feed the
        # known test passphrase; a no-op on a plaintext pool.
        printf '%s' "\$INSTALL_ENC_PASSPHRASE" | zfs load-key -a 2>/dev/null \\
          || true
        zfs mount rpool/ROOT/arch || true; _vroot=zfs
      else
        _rt="\$(blkid -o value -s TYPE /dev/disk/by-partlabel/root)"
        if [ "\$_rt" = crypto_LUKS ]; then
          # An encrypted (LUKS) ext4/xfs/btrfs root exposes a container at the
          # 'root' partlabel — open it with the test passphrase before mounting,
          # else the sentinel lands nowhere (combination-matrix/07).
          printf '%s' "\$INSTALL_ENC_PASSPHRASE" \\
            | cryptsetup open /dev/disk/by-partlabel/root cryptroot \\
                2>/dev/null || true
          _mt="\$(blkid -o value -s TYPE /dev/mapper/cryptroot)"
          if [ "\$_mt" = btrfs ]; then
            mount -o subvol=@ /dev/mapper/cryptroot /mnt || true; _vroot=plain
          else
            mount /dev/mapper/cryptroot /mnt || true; _vroot=plain
          fi
        elif [ "\$_rt" = btrfs ]; then
          # A btrfs root keeps the OS in subvol @ (ADR 0043); mount that, not
          # the top-level subvol, or the sentinel lands where /etc doesn't
          # exist.
          mount -o subvol=@ /dev/disk/by-partlabel/root /mnt || true; _vroot=plain
        else
          mount /dev/disk/by-partlabel/root /mnt || true; _vroot=plain
        fi
      fi
$(_seed_generator_esp_serial_lines)
      mkdir -p /mnt/etc/systemd/system/multi-user.target.wants
      printf '%s\n' '[Unit]' 'Description=boot-verify sentinel (test-only)' 'After=multi-user.target' '[Service]' 'Type=oneshot' 'ExecStart=/usr/bin/bash -c "{ ${extras_check}${user_check}${desktop_check}${display_manager_check}${aur_check}echo ===DIAG-ZFS-IMPORT-DEPS===; systemctl show zfs-import-cache.service zfs-import-scan.service -p Id -p Requires -p After; echo ===DIAG-UDEV-SETTLE===; grep -i settle /etc/initcpio/hooks/udev 2>/dev/null || echo NO-UDEV-OVERRIDE-HOOK; echo ${marker}; } > /dev/ttyS0 2>&1"' 'ExecStartPost=/usr/bin/systemctl disable firstboot-ok.service' '[Install]' 'WantedBy=multi-user.target' > /mnt/etc/systemd/system/firstboot-ok.service
      ln -sf ../firstboot-ok.service /mnt/etc/systemd/system/multi-user.target.wants/firstboot-ok.service
      if [ "\$_vroot" = zfs ]; then
        zfs umount -a || true
        zpool export rpool || zpool export -f rpool || true
      else
        umount -R /mnt || true
      fi
    fi
BLOCK
}

# Render the MULTI-disk first-boot verify block (issue 06 / ADR 0027). Re-import
# the freshly installed root pool at an altroot, install the unit-tested pool
# verifier (lib/vm-pool-verify.sh) plus an env file baking the expected pools +
# mounts into the target, drop a self-disabling oneshot that runs the verifier
# and echoes the boot sentinel ONLY when it passes, then export. A failed verify
# emits no marker, so the host boot-verify times out and the test fails loudly.
# Args: <pools-space-list> <mounts-space-list> [byid] [owned-space-list].
# Test-only — never production.
_seed_generator_multi_firstboot_block() {
  local pools="$1" mounts="$2" byid="${3:-false}" owned="${4:-}"
  local filesystem_mounts="${5:-}"
  local marker="$SEED_GENERATOR_FIRSTBOOT_MARKER"
  local lib="/usr/local/lib/vm-pool-verify.sh"
  local env="/usr/local/lib/vm-pool-verify.env"
  # Runs on the booted installed system: load expectations + verifier, emit the
  # sentinel only on success (stderr → serial for debugging), always
  # self-disable.
  local exec=". ${env}; . ${lib};"
  exec+=" if vm_pool_verify 2>/dev/ttyS0; then echo ${marker} > /dev/ttyS0; fi;"
  exec+=" systemctl disable firstboot-ok.service"
  # VM_VERIFY_BYID=true additionally asserts every leaf vdev resolves via
  # /dev/disk/by-id — the regression guard for the multi-disk reorder bug
  # (ADR 0028). Emitted only when requested so legacy fixtures are untouched.
  local byid_line=""
  [[ "$byid" == "true" ]] && byid_line=" 'VM_VERIFY_BYID=true'"
  # VM_VERIFY_OWNED bakes "<mount>:<user>" pairs the verifier asserts are owned
  # by, and writable by, <user> (pool-owners, ADR 0031). Emitted only when set.
  local owned_line=""
  [[ -n "$owned" ]] && owned_line=" 'VM_VERIFY_OWNED=(${owned})'"
  # VM_VERIFY_FS_MOUNTS bakes plain mountpoints the verifier asserts are mounted
  # (non-ZFS data groups, ADR 0043: ext4/xfs/btrfs disks have no zpool/dataset
  # to query, only a findmnt mountpoint). Emitted only when set.
  local filesystem_mounts_line=""
  [[ -n "$filesystem_mounts" ]] \
    && filesystem_mounts_line=" 'VM_VERIFY_FS_MOUNTS=(${filesystem_mounts})'"
  cat <<BLOCK
    if [ "\$rc" -eq 0 ]; then
      zpool import -f -N -R /mnt rpool || true
      zfs mount rpool/ROOT/arch || true
$(_seed_generator_esp_serial_lines)
      install -Dm644 /root/dotfiles/.installer/vm/lib/vm-pool-verify.sh "/mnt${lib}"
      printf '%s\n' 'VM_VERIFY_POOLS=(${pools})' 'VM_VERIFY_MOUNTS=(${mounts})'${byid_line}${owned_line}${filesystem_mounts_line} > "/mnt${env}"
      mkdir -p /mnt/etc/systemd/system/multi-user.target.wants
      printf '%s\n' '[Unit]' 'Description=pool-verify sentinel (test-only)' 'After=zfs.target zfs-mount.service' 'Wants=zfs.target' '[Service]' 'Type=oneshot' 'ExecStart=/usr/bin/bash -c "${exec}"' '[Install]' 'WantedBy=multi-user.target' > /mnt/etc/systemd/system/firstboot-ok.service
      ln -sf ../firstboot-ok.service /mnt/etc/systemd/system/multi-user.target.wants/firstboot-ok.service
      zfs umount -a || true
      zpool export rpool || zpool export -f rpool || true
    fi
BLOCK
}

# Render the boot-resilience first-boot verify block (ADR 0038). Installs the
# unit-tested esp-resilience verifier and drops a self-disabling oneshot that
# composes the real hardened modules; it emits the sentinel ONLY when every
# guard fires (a critical ESP copy fails loud + preserves the prior image, and a
# planted Stray Kernel is detected). A regression emits no marker, so the host
# boot-verify times out and the test fails. Test-only — never production.
_seed_generator_esp_resilience_firstboot_block() {
  local marker="$SEED_GENERATOR_FIRSTBOOT_MARKER"
  local lib="/usr/local/lib/esp-resilience-verify.sh"
  local exec=". ${lib};"
  exec+=" if esp_resilience_verify 2>/dev/ttyS0; then echo ${marker} > /dev/ttyS0; fi;"
  exec+=" systemctl disable firstboot-ok.service"
  cat <<BLOCK
    if [ "\$rc" -eq 0 ]; then
      zpool import -f -N -R /mnt rpool || true
      zfs mount rpool/ROOT/arch || true
$(_seed_generator_esp_serial_lines)
      install -Dm644 /root/dotfiles/.installer/vm/lib/esp-resilience-verify.sh "/mnt${lib}"
      mkdir -p /mnt/etc/systemd/system/multi-user.target.wants
      printf '%s\n' '[Unit]' 'Description=boot-resilience verify sentinel (test-only)' 'After=multi-user.target' '[Service]' 'Type=oneshot' 'ExecStart=/usr/bin/bash -c "${exec}"' '[Install]' 'WantedBy=multi-user.target' > /mnt/etc/systemd/system/firstboot-ok.service
      ln -sf ../firstboot-ok.service /mnt/etc/systemd/system/multi-user.target.wants/firstboot-ok.service
      zfs umount -a || true
      zpool export rpool || zpool export -f rpool || true
    fi
BLOCK
}

# Render the IMPERMANENCE ROLLBACK first-boot verify block (ADR 0044). A
# stateful two-phase sentinel that proves the boot-time @blank rollback works:
#   boot1 — write a probe to <probe_dir> (a Rollback Dataset path; default /opt)
#           AND a phase flag to /persist (the never-rolled-back Persist Dataset),
#           then reboot.
#   boot2 — the initramfs zfs-rollback hook reverts <probe_dir> to @blank; the
#           unit asserts the probe is GONE and the /persist flag SURVIVED, and
#           ONLY then emits the boot marker.
# The probe SURVIVING (e.g. <probe_dir>=/persist — the negative control) yields
# no marker, so the host boot-verify times out = RED, proving the assertion is
# not vacuous. The unit + its wants symlink live under /usr/lib/systemd/system
# (the root dataset, never rolled back — [[impermanence-service-enable]]) so
# they survive BOTH boots; phase 2 self-disables. Test-only — never production.
# Args: [probe_directory] (default /opt) [break_blank] (default false)
# [filesystem] (default zfs). With break_blank=true, boot1 also destroys the
# @blank for the /etc rollback container so boot2's initramfs rollback hook
# fails closed (missing @blank → emergency shell) → no marker → host RED: the
# hook-level fault control proving a REAL broken rollback can't false-PASS. On
# btrfs the container is a subvolume, so the break deletes the top-level
# @etc@blank subvol (mounted subvolid=5 at /mnt) instead of `zfs destroy`. The
# seed step that drops the sentinel unit also goes FS-conditional: zfs imports
# rpool, btrfs mounts subvol=@ from the GPT partlabel 'root' (plaintext rollback
# VMs only). Paths carry no spaces (no quoting needed in the single-quoted
# ExecStart printf arg).
_seed_generator_rollback_firstboot_block() {
  local probe_directory="${1:-/opt}" break_blank="${2:-false}" \
    filesystem="${3:-zfs}"
  local marker="$SEED_GENERATOR_FIRSTBOOT_MARKER"
  local break_step=""
  if [[ "$break_blank" == "true" ]]; then
    if [[ "$filesystem" == "btrfs" ]]; then
      # /mnt is free on the booted system; mount the btrfs top-level there to
      # reach @etc@blank, delete it, unmount.
      break_step=" mount -o subvolid=5 /dev/disk/by-partlabel/root /mnt;"
      break_step+=" btrfs subvolume delete /mnt/@etc@blank; umount /mnt;"
    else
      break_step=" zfs destroy rpool/ROOT/etc@blank;"
    fi
  fi
  local exec="if [ ! -e /persist/.rollback-phase ]; then"
  exec+=" mkdir -p ${probe_directory} /persist;"
  exec+=" : > ${probe_directory}/.rollback-probe; : > /persist/.rollback-phase; sync;"
  exec+="${break_step}"
  exec+=" systemctl --no-block reboot;"
  exec+=" else"
  exec+=" if [ ! -e ${probe_directory}/.rollback-probe ] && [ -e /persist/.rollback-phase ];"
  exec+=" then echo ${marker} > /dev/ttyS0; fi;"
  exec+=" systemctl disable firstboot-ok.service;"
  exec+=" fi"
  # The seed step mounts the installed root to drop the sentinel unit under
  # /usr/lib (the never-rolled-back root subvol/dataset, survives both boots).
  local mount_step unmount_step
  if [[ "$filesystem" == "btrfs" ]]; then
    # Scan first so a multi-device raid root assembles before the subvol=@ mount
    # (no-op on a single disk). The partlabel resolves to any one member; btrfs
    # mounts the whole assembled fs from it.
    mount_step="btrfs device scan || true
      mount -o subvol=@ /dev/disk/by-partlabel/root /mnt || true"
    unmount_step="umount -R /mnt || true"
  else
    mount_step="zpool import -f -N -R /mnt rpool || true
      zfs mount rpool/ROOT/arch || true"
    unmount_step="zfs umount -a || true
      zpool export rpool || zpool export -f rpool || true"
  fi
  cat <<BLOCK
    if [ "\$rc" -eq 0 ]; then
      ${mount_step}
$(_seed_generator_esp_serial_lines)
      mkdir -p /mnt/usr/lib/systemd/system/multi-user.target.wants
      printf '%s\n' '[Unit]' 'Description=rollback-verify sentinel (test-only)' 'After=multi-user.target' '[Service]' 'Type=oneshot' 'ExecStart=/usr/bin/bash -c "${exec}"' '[Install]' 'WantedBy=multi-user.target' > /mnt/usr/lib/systemd/system/firstboot-ok.service
      ln -sf ../firstboot-ok.service /mnt/usr/lib/systemd/system/multi-user.target.wants/firstboot-ok.service
      ${unmount_step}
    fi
BLOCK
}
