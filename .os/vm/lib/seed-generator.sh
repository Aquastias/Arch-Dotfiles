#!/usr/bin/env bash
# =============================================================================
# lib/seed-generator.sh — Cloud-init NoCloud seed-ISO builder
# =============================================================================
# Public:
#   seed_generator_build REPO_URL HOSTNAME OUTPUT_DIR
#       Render a cloud-init `user-data` document parameterised by REPO_URL
#       and HOSTNAME, build a NoCloud `seed.iso` from it via cloud-localds,
#       and print the absolute path of the produced ISO on stdout.
#
#       The runcmd inside the user-data:
#         - cd into a clean clone of REPO_URL at /root/dotfiles
#         - patch install.jsonc's hostname to HOSTNAME
#         - run install.sh --unattended
#         - emit `===INSTALLER-EXIT-N===` to /dev/ttyS0
#         - sync and poweroff -f
#
#       The exact line `===INSTALLER-EXIT-N===` is the contract consumed by
#       lib/sentinel-watcher.sh on the host. Do not change the format.
#
#       Returns non-zero if `cloud-localds` is missing — the orchestrator,
#       not this module, is responsible for installing it.
#
# Test seam:
#   _seed_generator_render_user_data REPO_URL HOSTNAME
#       Echo the user-data document text without invoking cloud-localds.
#       Tests use this to assert substitution and runcmd shape without
#       requiring cloud-image-utils on the test host.
# =============================================================================

# ── Internal: render user-data text ───────────────────────────────────────────
#
# Two cloud-init mechanisms work together to make installer output reach the
# host's serial-console capture:
#
# 1. `output: {all: '| tee -a /dev/ttyS0'}` — routes cloud-init's own stdio
#    (including all runcmd output) to /dev/ttyS0 as well as the on-VM log.
#    Without this, runcmd output lands only in
#    /var/log/cloud-init-output.log inside the VM, where the host's
#    `virsh console` cannot see it.
#
# 2. A single multiline runcmd entry — each entry in cloud-init's runcmd list
#    is invoked in its own shell, so a lone `exec > /dev/ttyS0 2>&1` only
#    redirects that one shell. Bundling every step into one `|` block keeps
#    `cd`, `$rc`, and `set -ex` working as a normal script.

# Marker the test-only first-boot unit echoes to /dev/ttyS0 once the installed
# system boots. The host boot-verify phase waits for it via
# sentinel_watcher_wait_marker. A hard contract like INSTALLER-EXIT — keep it
# in sync with vm/lib/flow-test.sh.
SEED_GENERATOR_FIRSTBOOT_MARKER='===FIRSTBOOT-OK==='

# (test-only) Append a serial console to the installed kernel cmdline so the
# boot-verify phase can observe the boot. The product cmdline carries no
# console=ttyS0 (systemd-boot itself prints to serial, but once the kernel
# starts the serial goes dark), so the host sees only the boot menu then 600 s
# of silence — even the first-boot sentinel write was invisible. Mount the ESP
# holding systemd-boot's loader entries and add console=ttyS0 last so /dev/console
# (kernel logs, systemd, emergency prompts, and the sentinel) lands on serial.
# Emitted as 6-space-indented runcmd lines; runs on the live ISO with the
# installed root already mounted at /mnt. Single-quoted heredoc: the inner $/$()
# are literal, evaluated on the VM, not at render time.
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
  local m="$SEED_GENERATOR_FIRSTBOOT_MARKER" verify_user="${1:-}"
  local verify_extras="${2:-}"
  local user_check=""
  [[ -n "$verify_user" ]] && user_check="if id ${verify_user} > /dev/null 2>&1 && passwd -S ${verify_user} 2>/dev/null | grep -qw P; then echo ===USER-OK===; else echo ===USER-FAIL===; fi; "
  # Security & Backup Extras check (issue 04/05): every named unit must be
  # is-enabled on the booted system. A single `systemctl is-enabled u1 u2 …`
  # exits 0 only when ALL are enabled — so one call, no loop, no single quotes
  # (the ExecStart is a single-quoted printf arg), like user_check above.
  local extras_check=""
  [[ -n "$verify_extras" ]] && extras_check="if systemctl is-enabled ${verify_extras} > /dev/null 2>&1; then echo ===EXTRAS-OK===; else echo ===EXTRAS-FAIL===; fi; "
  cat <<BLOCK
    if [ "\$rc" -eq 0 ]; then
      # Mount the freshly installed root to inject the sentinel: a ZFS root via
      # pool import, a non-ZFS (ext4/xfs/btrfs) root via its GPT partlabel 'root'
      # the Root Layout Adapter set (ADR 0043).
      if zpool import -f -N -R /mnt rpool 2>/dev/null; then
        zfs mount rpool/ROOT/arch || true; _vroot=zfs
      elif [ "\$(blkid -o value -s TYPE /dev/disk/by-partlabel/root)" = btrfs ]; then
        # A btrfs root keeps the OS in subvol @ (ADR 0043); mount that, not the
        # top-level subvol, or the sentinel unit lands where /etc doesn't exist.
        mount -o subvol=@ /dev/disk/by-partlabel/root /mnt || true; _vroot=plain
      else
        mount /dev/disk/by-partlabel/root /mnt || true; _vroot=plain
      fi
$(_seed_generator_esp_serial_lines)
      mkdir -p /mnt/etc/systemd/system/multi-user.target.wants
      printf '%s\n' '[Unit]' 'Description=boot-verify sentinel (test-only)' 'After=multi-user.target' '[Service]' 'Type=oneshot' 'ExecStart=/usr/bin/bash -c "{ ${extras_check}${user_check}echo ===DIAG-ZFS-IMPORT-DEPS===; systemctl show zfs-import-cache.service zfs-import-scan.service -p Id -p Requires -p After; echo ===DIAG-UDEV-SETTLE===; grep -i settle /etc/initcpio/hooks/udev 2>/dev/null || echo NO-UDEV-OVERRIDE-HOOK; echo ${m}; } > /dev/ttyS0 2>&1"' 'ExecStartPost=/usr/bin/systemctl disable firstboot-ok.service' '[Install]' 'WantedBy=multi-user.target' > /mnt/etc/systemd/system/firstboot-ok.service
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
  local fs_mounts="${5:-}"
  local m="$SEED_GENERATOR_FIRSTBOOT_MARKER"
  local lib="/usr/local/lib/vm-pool-verify.sh"
  local env="/usr/local/lib/vm-pool-verify.env"
  # Runs on the booted installed system: load expectations + verifier, emit the
  # sentinel only on success (stderr → serial for debugging), always self-disable.
  local exec=". ${env}; . ${lib};"
  exec+=" if vm_pool_verify 2>/dev/ttyS0; then echo ${m} > /dev/ttyS0; fi;"
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
  # (non-ZFS data groups, ADR 0043: ext4/xfs/btrfs disks have no zpool/dataset to
  # query, only a findmnt mountpoint). Emitted only when set.
  local fs_mounts_line=""
  [[ -n "$fs_mounts" ]] && fs_mounts_line=" 'VM_VERIFY_FS_MOUNTS=(${fs_mounts})'"
  cat <<BLOCK
    if [ "\$rc" -eq 0 ]; then
      zpool import -f -N -R /mnt rpool || true
      zfs mount rpool/ROOT/arch || true
$(_seed_generator_esp_serial_lines)
      install -Dm644 /root/dotfiles/.os/vm/lib/vm-pool-verify.sh "/mnt${lib}"
      printf '%s\n' 'VM_VERIFY_POOLS=(${pools})' 'VM_VERIFY_MOUNTS=(${mounts})'${byid_line}${owned_line}${fs_mounts_line} > "/mnt${env}"
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
  local m="$SEED_GENERATOR_FIRSTBOOT_MARKER"
  local lib="/usr/local/lib/esp-resilience-verify.sh"
  local exec=". ${lib};"
  exec+=" if esp_resilience_verify 2>/dev/ttyS0; then echo ${m} > /dev/ttyS0; fi;"
  exec+=" systemctl disable firstboot-ok.service"
  cat <<BLOCK
    if [ "\$rc" -eq 0 ]; then
      zpool import -f -N -R /mnt rpool || true
      zfs mount rpool/ROOT/arch || true
$(_seed_generator_esp_serial_lines)
      install -Dm644 /root/dotfiles/.os/vm/lib/esp-resilience-verify.sh "/mnt${lib}"
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
#   boot1 — write a probe to <probe_dir> (a Rollback Dataset path; default /root)
#           AND a phase flag to /persist (the never-rolled-back Persist Dataset),
#           then reboot.
#   boot2 — the initramfs zfs-rollback hook reverts <probe_dir> to @blank; the
#           unit asserts the probe is GONE and the /persist flag SURVIVED, and
#           ONLY then emits the boot marker.
# The probe SURVIVING (e.g. <probe_dir>=/persist — the negative control) yields
# no marker, so the host boot-verify times out = RED, proving the assertion is
# not vacuous. The unit + its wants symlink live under /usr/lib/systemd/system
# (the root dataset, never rolled back — [[impermanence-service-enable]]) so they
# survive BOTH boots; phase 2 self-disables. Test-only — never production.
# Args: [probe_dir] (default /root) [break_blank] (default false) [filesystem]
# (default zfs). With break_blank=true, boot1 also destroys the @blank for the
# /etc rollback container so boot2's initramfs rollback hook fails closed (missing
# @blank → emergency shell) → no marker → host RED: the hook-level fault control
# proving a REAL broken rollback can't false-PASS. On btrfs the container is a
# subvolume, so the break deletes the top-level @etc@blank subvol (mounted
# subvolid=5 at /mnt) instead of `zfs destroy`. The seed step that drops the
# sentinel unit also goes FS-conditional: zfs imports rpool, btrfs mounts subvol=@
# from the GPT partlabel 'root' (plaintext rollback VMs only). Paths carry no
# spaces (no quoting needed in the single-quoted ExecStart printf arg).
_seed_generator_rollback_firstboot_block() {
  local probe_dir="${1:-/root}" break_blank="${2:-false}" filesystem="${3:-zfs}"
  local m="$SEED_GENERATOR_FIRSTBOOT_MARKER"
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
  exec+=" mkdir -p ${probe_dir} /persist;"
  exec+=" : > ${probe_dir}/.rollback-probe; : > /persist/.rollback-phase; sync;"
  exec+="${break_step}"
  exec+=" systemctl --no-block reboot;"
  exec+=" else"
  exec+=" if [ ! -e ${probe_dir}/.rollback-probe ] && [ -e /persist/.rollback-phase ];"
  exec+=" then echo ${m} > /dev/ttyS0; fi;"
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

_seed_generator_render_user_data() {
  local repo_url="$1" hostname="$2"
  local dirty_cache="${3:-false}" verify_boot="${4:-false}"

  # Optional: corrupt the live ISO's zpool.cache before the installer runs, to
  # reproduce the dirty-ISO condition the per-pool seeding fix must survive.
  # Chained with && so a write failure still short-circuits into the sentinel.
  local dirty_step=""
  [[ "$dirty_cache" == "true" ]] && \
    dirty_step='mkdir -p /etc/zfs && printf %s garbage-not-an-nvlist'
  [[ -n "$dirty_step" ]] && \
    dirty_step="${dirty_step} > /etc/zfs/zpool.cache && "

  # Optional: inject the first-boot sentinel unit after a successful install.
  local boot_block=""
  [[ "$verify_boot" == "true" ]] && \
    boot_block="$(_seed_generator_firstboot_block)"

  cat <<EOF
#cloud-config
# Generated by .os/lib/seed-generator.sh — do not edit by hand.
# Consumed by archiso's NoCloud datasource on first boot.
# set -e is intentionally OFF: a setup-step failure under it would abort
# this shell before the sentinel + poweroff path runs, leaving the host
# harness to wait the full timeout. The chain below short-circuits on
# first failure; rc captures the failed step's exit code; the sentinel is
# always emitted; the VM always powers off. set -x keeps traceability.
output: {all: '| tee -a /dev/ttyS0'}
runcmd:
  - |
    set +e
    set -x
    {
      pacman -Sy --noconfirm --needed git \\
        && rm -rf /root/dotfiles \\
        && git clone ${repo_url} /root/dotfiles \\
        && cd /root/dotfiles/.os \\
        && sed -i \
  's|"hostname"[[:space:]]*:[[:space:]]*"[^"]*"|"hostname": "${hostname}"|' \
  install.jsonc \\
        && ${dirty_step}./install.sh --unattended install.jsonc
    }
    rc=\$?
${boot_block}
    printf '===INSTALLER-EXIT-%d===\n' "\$rc" > /dev/ttyS0
    sync
    poweroff -f
EOF
}

# Render the GUIDED Installer cloud-init runcmd (issue 01b). Instead of
# injecting an install.jsonc and running install.sh positionally, this drives
# the Guided Installer headlessly: it resolves the install disk in-guest via
# the Pre-Install Picker (picker_enum_disks — pure bash, no jq, so it works
# before 01-bootstrap), writes a replay answers file (hostname / disk /
# INSTALL), and runs `install.sh --guided`. The shell replays the answers
# through guided_select/guided_prompt — no fzf, no tty — and assembles the same
# single-disk Effective Config. The firstboot block + sentinel + poweroff are
# shared with the non-guided renderer. Test-only — never production.
# Args: <repo_url> <hostname> [dirty_cache] [verify_boot] [encryption]
#       [impermanence]. encryption/impermanence "true" append the matching guided
# answer (so the replayed menu sets them); encryption also presets
# INSTALL_ENC_PASSPHRASE — the back-end's non-interactive passphrase seam — so
# the ZFS native-encrypted pool is created without a tty prompt (test-only).
_seed_generator_render_guided_user_data() {
  local repo_url="$1" hostname="$2"
  local dirty_cache="${3:-false}" verify_boot="${4:-false}"
  local encryption="${5:-false}" impermanence="${6:-false}"
  local layout="${7:-single}" n_disks="${8:-1}" guided_user="${9:-}"
  local guided_extras="${10:-}"

  local dirty_step=""
  [[ "$dirty_cache" == "true" ]] && \
    dirty_step='mkdir -p /etc/zfs && printf %s garbage-not-an-nvlist'
  [[ -n "$dirty_step" ]] && \
    dirty_step="${dirty_step} > /etc/zfs/zpool.cache && "

  # Extra guided answers replayed before INSTALL, plus the passphrase preset the
  # encrypted-pool path needs (mirrors the non-guided test flow).
  # Single backslash: these are substituted into the heredoc as-is (heredoc
  # backslash processing applies only to its literal text), so the guest's
  # printf sees `\n` and writes one answer per line.
  local extra_answers="" enc_export=""
  [[ "$encryption" == "true" ]] && {
    extra_answers+='encryption=true\n'
    enc_export="export INSTALL_ENC_PASSPHRASE='testtest' && "
  }
  [[ "$impermanence" == "true" ]] && extra_answers+='impermanence=true\n'

  # Ad-hoc user + passwords (issue 07): when the profile names a guided_user,
  # replay the create-user form keys + the root password so the guided menu
  # authors the user and the no-SOPS injector sets both passwords. verify_user
  # drives the USER-OK boot check below.
  local verify_user=""
  if [[ -n "$guided_user" && "$guided_user" != "null" ]]; then
    local u_name u_pw u_sudo u_shell r_pw
    u_name="$(jq -r '.name // empty' <<<"$guided_user")"
    u_pw="$(jq -r '.password // "12345"' <<<"$guided_user")"
    u_sudo="$(jq -r '.sudo // false' <<<"$guided_user")"
    u_shell="$(jq -r '.shell // "/bin/bash"' <<<"$guided_user")"
    r_pw="$(jq -r '.root_password // empty' <<<"$guided_user")"
    extra_answers+="new_user_name=${u_name}\\n"
    extra_answers+="new_user_shell=${u_shell}\\n"
    extra_answers+="new_user_sudo=${u_sudo}\\n"
    extra_answers+="new_user_password=${u_pw}\\n"
    [[ -n "$r_pw" ]] && extra_answers+="root_password=${r_pw}\\n"
    verify_user="$u_name"
  fi

  # Security & Backup Extras smoke (issue 04/05): guided_extras re-picks a
  # minimal committed user (users=…, so users[0] is light, not aquastias's full
  # set), replays toggle overrides (answers: e.g. borg=false), and names the
  # daemons the boot-verify must find enabled (verify[] → EXTRAS-OK/FAIL).
  local verify_extras=""
  if [[ -n "$guided_extras" && "$guided_extras" != "null" ]]; then
    local gx_users gx_verify
    gx_users="$(jq -r '.users // empty' <<<"$guided_extras")"
    [[ -n "$gx_users" ]] && extra_answers+="users=${gx_users}\\n"
    while IFS= read -r _kv; do
      [[ -n "$_kv" ]] && extra_answers+="${_kv}\\n"
    done < <(jq -r '(.answers // {}) | to_entries[] | "\(.key)=\(.value)"' \
      <<<"$guided_extras")
    gx_verify="$(jq -r '(.verify // []) | join(" ")' <<<"$guided_extras")"
    verify_extras="$gx_verify"
  fi

  # The disk-resolution + answers-file step differs by layout. Built in its own
  # heredoc so the \$ / \\n / \\ escapes are processed identically to the outer
  # one, then embedded verbatim. single resolves one disk (disk=); a multi
  # preset resolves N disks (head -N), replays the layout + a whitespace device
  # list (disks=), and gates on a typed ACCEPT.
  local picker='source lib/picker.sh; source lib/live-medium.sh; set +e'
  local disk_step
  if [[ "$layout" != "single" ]]; then
    disk_step="$(cat <<EOF
&& GUIDED_DISKS="\$(${picker}; picker_enum_disks "\$(live_medium_disks)" | head -${n_disks} | tr '\\n' ' ')" \\
        && printf 'hostname=%s\\nlayout=${layout}\\ndisks=%s\\naccept_layout=ACCEPT\\n${extra_answers}confirm=INSTALL\\n' '${hostname}' "\$GUIDED_DISKS" > /root/guided-answers
EOF
)"
  else
    disk_step="$(cat <<EOF
&& GUIDED_DISK="\$(${picker}; picker_enum_disks "\$(live_medium_disks)" | head -1)" \\
        && printf 'hostname=%s\\ndisk=%s\\n${extra_answers}confirm=INSTALL\\n' '${hostname}' "\$GUIDED_DISK" > /root/guided-answers
EOF
)"
  fi

  local boot_block=""
  [[ "$verify_boot" == "true" ]] && \
    boot_block="$(_seed_generator_firstboot_block "$verify_user" "$verify_extras")"

  cat <<EOF
#cloud-config
# Generated by .os/lib/seed-generator.sh (guided) — do not edit by hand.
# Drives the Guided Installer headlessly: resolve the install disk(s) in-guest
# via the Pre-Install Picker, write a replay answers file, run install.sh
# --guided. set -e is intentionally OFF (see the non-guided renderer for why).
output: {all: '| tee -a /dev/ttyS0'}
runcmd:
  - |
    set +e
    set -x
    {
      pacman -Sy --noconfirm --needed git \\
        && rm -rf /root/dotfiles \\
        && git clone ${repo_url} /root/dotfiles \\
        && cd /root/dotfiles/.os \\
        ${disk_step} \\
        && cat /root/guided-answers \\
        && ${dirty_step}${enc_export}./install.sh --guided /root/guided-answers
    }
    rc=\$?
${boot_block}
    printf '===INSTALLER-EXIT-%d===\n' "\$rc" > /dev/ttyS0
    sync
    poweroff -f
EOF
}

# ── Public API ────────────────────────────────────────────────────────────────

seed_generator_build() {
  local repo_url="$1" hostname="$2" out_dir="$3"

  [[ -n "$repo_url" ]] || {
    echo "seed-generator: REPO_URL is empty" >&2
    return 1
  }
  [[ -n "$hostname" ]] || {
    echo "seed-generator: HOSTNAME is empty" >&2
    return 1
  }
  [[ -d "$out_dir" ]] || {
    echo "seed-generator: output directory does not exist: $out_dir" >&2
    return 1
  }

  command -v cloud-localds >/dev/null 2>&1 || {
    echo "seed-generator: cloud-localds not found —" \
         "install cloud-image-utils" >&2
    return 1
  }

  local user_data="${out_dir%/}/user-data"
  local seed_iso="${out_dir%/}/seed.iso"

  _seed_generator_render_user_data "$repo_url" "$hostname" > "$user_data"

  cloud-localds "$seed_iso" "$user_data" >/dev/null || {
    echo "seed-generator: cloud-localds failed for $user_data" >&2
    return 1
  }

  [[ -s "$seed_iso" ]] || {
    echo "seed-generator: cloud-localds produced no output at $seed_iso" >&2
    return 1
  }

  printf '%s\n' "$seed_iso"
}
