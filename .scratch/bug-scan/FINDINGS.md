# Bug scan findings

Status per area: [x] scanned. Findings: `ID sev file:line — summary`.

## Areas
- [x] lib/wipe, tools/impermanence.sh, lib/impermanence-common.sh (partial)
- [x] tools/install-pkglist.sh, tools/save-pkglist.sh, lib/secrets.sh
- [x] top-level 01/02/03/install.sh; lib/*.sh (common,jsonc,picker,preflight,finalize,install-state,chroot,live-medium); lib/config/*
- [x] lib/config lib/packages lib/boot lib/chroot
- [x] lib/layout lib/zfs
- [x] lib/profiles
- [x] extras/
- [x] programs/
- [x] lib/guided (targeted: secrets, session, assembly, users)
- [x] tools/ (all); vm/, lib/matrix, lib/feature-audit: pattern pass only (test harness)

## Findings
- ✔B1 high 01-bootstrap-zfs.sh:125 — ((waited++)) from 0 aborts under set -e
- B2 high impermanence-common.sh:216 / tools/impermanence.sh:192 — re-add
  nests cp -a into preserved /persist data; rollback rm -rf deletes it
- B3 med tools/impermanence.sh:254 — status zfs-only; false ERROR on btrfs
- B4 low lib/wipe/execute.sh:40,52 — substring disk match (sda~sdab)
- B5 low lib/layout/core.sh:77-101 — leading-zero size parsed as octal
- B6 low programs/system/zsh/install.sh:87 — cp -a nests on rerun
- B7 low lib/common.sh:148 — part_name lacks p for names ending in digit
- ✔B8 med 01-bootstrap-zfs.sh:133-152 — reachability loop waits 2.5s (half-s ticks) and never rechecks flag after wait → false 'no internet'
- ✔B9 high install.sh:~366 — `guided_build >f; status=$?` under set -e: Save/
  Export (rc 64) aborts with "aborted at line" + exit 64 instead of exit 0
- B10 med lib/wipe/execute.sh teardown_{zfs,lvm} — install-driven targets are
  /dev/disk/by-id paths; never match pvs (/dev/sdX) nor zpool vdev names
- B11 med lib/jsonc.sh jsonc_append_to_array — early "already present" grep matches value anywhere in file (other array/comment) → silent no-op
- B12 high lib/config/validation.sh:59 — RESOLVED_HOST_PROFILE=hostname, but
  profile≠hostname (desktop→eterniox, laptop→chronos, ADR 0020).
  install_state persist ← profile_loader_load(hostname) fails → {} (desktop's
  persist dirs dropped); secrets_load host/user lookup by hostname misses.
- B13 low lib/chroot.sh:205 — 90-paccache.hook written only when esp_count>1 (inside esp-mirror fn after early return); single-ESP installs never get cache cleanup
- B14 low lib/config/post-install.sh post_install_validate — jq inside() is substring-based: firewall "fire"/"uf"/"" pass validation → silently no firewall
- B15 med lib/config/manual-partition.sh manual_partition_target_disk (guided cfdisk, fzf-entry.sh:105) — always first by-id disk; ADR 0073 says operator picks target disk
  (B12 also: _validation_preflight_programs silently skips for desktop/laptop)
- B16 trivial lib/config/lifecycle.sh _lifecycle_print_extras — awk join alternates "," and " " (a,b c,d)
- B17 med lib/config/environment.sh _environment_gpu_detect_vendors — greps all lspci lines (not VGA/3D/Display class): Intel chipset/NIC/QEMU bridge → "intel"; intel refine uses first Intel device of any kind
- B18 low lib/packages/package-list.sh _package_list_clean_target_cache — CleanMethod sed on target pacman.conf is overwritten later by chroot_configure_system cp /etc/pacman.conf
- ✔B19 med lib/packages/archzfs-kernel.sh archzfs_kernel_lts_pin_prepare — chosen="$(build_repository)" under set -e: build failure aborts install; documented "proceeding unpinned" fallback unreachable
- B20 low lib/packages/gpu.sh — nvidia set includes lib32-nvidia-utils; with optional_repos lacking multilib pacstrap fails after disks are partitioned (no guard)
- B21 trivial lib/packages/package-resolver.sh _package_resolver_user_shells — no users/vm/<name> fallback
- B22 low lib/chroot/identity.sh — X11 XkbLayout written from console keymap names (de-latin1, uk, fr-latin9 ≠ xkb de, gb, fr) → invalid layout
- B23 CRITICAL lib/boot/esp-kernel-sync.sh esp_kernel_sync_planned_files — plans only from loader/entries/*.conf (systemd-boot); grub/limine/refind/efistub ESPs never receive upgraded vmlinuz/initramfs → stale kernel w/o modules → unbootable after first kernel upgrade
- B24 low lib/impermanence-common.sh persist_unapply — awk uses target path as regex ("." etc.) → may drop other tmpfiles entries
- ✔B25 low lib/impermanence-common.sh persist_stage_in_move — `((n)) && mv` last in subshell exits 1 for an empty mountpoint source → aborts under set -e
- B26 med lib/layout/zfs/single.sh:212 — OS size passed as +N 512-byte "s"; sgdisk sectors are logical (4096 on 4Kn) → OS partition 8× too big / fails
- B27 low lib/layout/zfs/single.sh (and others) — partprobe; sleep 2 then mkfs on by-id -partN symlink: races udev (no udevadm settle)
- B28 med lib/zfs/pools.sh zfs_vdev_spec mirror — builds one N-way mirror; menu promises "2 × 2-disk mirrors"/even-count striped mirrors (4 disks → 1 disk capacity)
- B29 med lib/zfs/pools.sh zfs_vdev_spec — no "raidz" case; storage group topology "raidz" passes validation (_validation_topology_for_filesystem, picker) then errors after disks are wiped
- B30 med lib/zfs/pools.sh zfs_create_os_datasets — swap zvol recomputed RAM×2 uncapped; single-layout's disk/4 cap ignored → zvol can exceed rpool
- B31 low lib/layout/zfs/multi-validate.sh — duplicate disk check only when data_pools>0; os_pool∩storage_groups disk not caught → OS partitions zapped
- ✔B32 high lib/zfs/pool-owners.sh zfs_pool_owners_mode ((token_count++)) from 0 inside $(...) + 03-install ERR trap (set -E, exit 1, no BASH_SUBSHELL guard) → any `owners` on a pool aborts install at ownership step. Root cause: 01/03 _on_error lacks install.sh's `(( BASH_SUBSHELL == 0 )) || return` guard, so ERR fires+exits inside command substitutions.
- B33 med lib/layout/nonzfs/boot.sh + zfs/plan.sh _layout_publish_boot — HOOKS lack `keymap` (consolefont): boot-time LUKS/ZFS passphrase prompt is always US layout regardless of system.keymap
- B34 med lib/layout/btrfs/multi.sh — never resolves/partitions/creates data_pools (other adapters do) → data pools silently ignored
- B35 low lib/layout/btrfs/multi.sh layout_mount_esp — secondary ESPs formatted but never mounted; install-time mirror rsync lands on root fs, no UEFI entries for mirrors
- B36 med README.md:283 vs lib/profiles/runner.sh — README says default user password 12345 is "changed on first login"; nothing expires it (no chage -d 0); profile installs silently get 12345
- B37 low extras/desktop/niri/niri.sh + dm/greetd — KDE+niri (no hyprland) with explicit greetd: curated dir has only niri.desktop (only hyprland.sh links plasma.desktop) → tuigreet hides Plasma
- B38 low programs/virtualization/virt-manager/install.sh — /etc/polkit-1/rules.d/50-libvirt.rules (kvm group) shadows libvirt pkg rule of same name (libvirt group) → users in libvirt but not kvm lose passwordless access
- B39 low programs/backup/zfs-auto-snapshot/install.sh — tag service hardcodes rpool; custom os pool name → nothing snapshotted
- B40 trivial programs/dev/claude/install.sh — print_status "warn" (not a type; should be "warning") → no prefix/colour
- B41 low programs/virtualization/podman/install.sh — every user gets the same subuid/subgid range 100000-165535 → overlapping ranges for 2+ podman users
- B42 med programs/security/rkhunter/scripts/rkhunter_scan.sh — greps whole appended /var/log/rkhunter.log for "Warning:" → after any warning ever, every run alerts
- B43 high programs/security/rkhunter/scripts/rkhunter_scan.sh — runs `rkhunter --propupd` right before `--check` each scan → re-baselines file properties, file-change detection never fires
- B44 med programs/security/clamav/scripts/clamav_daily_scan.sh — send_user_notification args shifted (icon="Check latest log…", timeout="ClamAV Daily Scan") → notify-send -t parse error, infection alert never shown
- B45 med lib/guided/controller-enter-values.sh _controller_accept_new_user_name + shell-users.sh _guided_shell_create_user — no username format validation (spaces, uppercase, root, quotes, ../) → fails late at useradd / breaks jq path after disks wiped
- B46 med install.sh run_numbered_phases — 02-wipe zeroes target disks before 03's validation_check_install_context; config errors (guided/CLI configs) surface after data is destroyed
