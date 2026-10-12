#!/usr/bin/env bash
# =============================================================================
# lib/chroot/impermanence-boot-hooks.sh — the impermanence boot-time pieces
# =============================================================================
# Used by: lib/chroot/impermanence.sh (sources it). Writes the initramfs
# rollback hook (zfs or btrfs) and the pacman resnapshot helper + hook that
# keep each @blank snapshot current. The hook/helper bodies are heredoc
# templates, written verbatim into the new root.
# =============================================================================

# FS-conditional rollback hook (ADR 0044): write the zfs-rollback or the
# btrfs-rollback initramfs hook. Both honour the same contract — roll every
# curated path back to its @blank on boot, failing closed to an emergency shell
# on a missing @blank. The HOOKS list (the Root Adapter) names the matching
# hook.
impermanence_boot_hooks_write_rollback() {
  if [[ "${FILESYSTEM:-zfs}" == "btrfs" ]]; then
    _impermanence_boot_hooks_write_rollback_btrfs
  else
    _impermanence_boot_hooks_write_rollback_zfs
  fi
}

_impermanence_boot_hooks_write_rollback_zfs() {
  local install_directory="${ROOT:-}/usr/lib/initcpio/install"
  local hooks_directory="${ROOT:-}/usr/lib/initcpio/hooks"
  mkdir -p "$install_directory" "$hooks_directory"

  cat > "$install_directory/zfs-rollback" <<'INSTALL'
#!/bin/bash
build() {
  add_runscript
}
help() {
  cat <<HELP
Rolls back curated ZFS datasets to @blank on every boot, then mounts them
(plus /var and /var/log) under /new_root so PID1 boots on a populated /etc
with the frozen machine-id. Fails closed to an emergency shell if any
@blank snapshot is missing.
HELP
}
INSTALL

  # Bake the dataset + mount lists into the runtime hook (no cmdline lookup).
  local entry suffix mountpoint dataset_list="" mount_pairs=""
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    mountpoint="${entry#*:}"
    dataset_list+="$RPOOL/ROOT/$suffix "
    mount_pairs+="$RPOOL/ROOT/$suffix=$mountpoint "
  done
  dataset_list="${dataset_list% }"
  # /var + /var/log are NOT rollback datasets, but they are separate datasets
  # that otherwise mount post-pivot (via zfs-mount) AFTER PID1/journald start —
  # too late: dbus's machine-id (/var/lib/dbus) and the journal (/var/log) then
  # land on the wrong/empty tree. Mount them early too; /var before /var/log.
  mount_pairs+="$RPOOL/var=/var $RPOOL/var/log=/var/log"

  # Must be run_latehook: the archzfs zfs hook only imports the pool in
  # its own run_latehook, so during run_hook the pool isn't available and
  # `zfs list` fails. HOOKS= order still applies (zfs latehook → ours).
  #
  # After rollback, MOUNT the datasets under /new_root before switch_root
  # (parity with the btrfs hook, ADR 0044). They are SEPARATE datasets that
  # otherwise mount post-pivot via zfs-mount — after PID1 and journald start.
  # PID1 then reads an EMPTY /etc (bare mountpoint on the root dataset), mints a
  # TRANSIENT machine-id, and dbus/logind/journald key off an unstable id → the
  # graphical login can't seat a session (black screen) and journald orphans its
  # journal onto the soon-shadowed /var/log. Mounting here gives PID1 the frozen
  # machine-id + a populated /etc; systemd adopts the already-mounted paths.
  cat > "$hooks_directory/zfs-rollback" <<HOOK
#!/usr/bin/ash
run_latehook() {
  local datasets="$dataset_list"
  local mounts="$mount_pairs"
  local ds pair mp
  for ds in \$datasets; do
    if ! zfs list -t snapshot "\${ds}@blank" >/dev/null 2>&1; then
      err "impermanence: @blank snapshot missing for \${ds}"
      launch_interactive_shell
    fi
    zfs rollback -r "\${ds}@blank"
  done
  for pair in \$mounts; do
    ds="\${pair%%=*}"
    mp="\${pair#*=}"
    zfs list -H -o name "\$ds" >/dev/null 2>&1 || continue
    mkdir -p "/new_root\${mp}"
    mount -t zfs -o zfsutil,rw "\$ds" "/new_root\${mp}" ||
      err "impermanence: could not mount \$ds at /new_root\${mp}"
  done
}
HOOK
}

_impermanence_boot_hooks_write_rollback_btrfs() {
  local install_directory="${ROOT:-}/usr/lib/initcpio/install"
  local hooks_directory="${ROOT:-}/usr/lib/initcpio/hooks"
  mkdir -p "$install_directory" "$hooks_directory"

  cat > "$install_directory/btrfs-rollback" <<'INSTALL'
#!/bin/bash
build() {
  add_runscript
}
help() {
  cat <<HELP
Rolls back curated btrfs subvolumes to their @blank on every boot. Fails
closed to an emergency shell if any @blank snapshot is missing.
HELP
}
INSTALL

  # Bake the rollback subvol list (and the subvol→mountpoint pairs the latehook
  # needs) into the runtime hook.
  local entry suffix mountpoint subvolume_list="" mountpoint_pairs=""
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    mountpoint="${entry#*:}"
    subvolume_list+="@$suffix "
    mountpoint_pairs+="@$suffix:$mountpoint "
  done
  subvolume_list="${subvolume_list% }"
  mountpoint_pairs="${mountpoint_pairs% }"

  # run_hook (not latehook): reset the subvols on the btrfs top-level before
  # `filesystems` pivots into the root. The kernel root= device is resolved with
  # the stock initcpio resolve_device/getarg helpers (handles UUID= plaintext
  # and the /dev/mapper/cryptroot the encrypt hook already opened). A read-only
  # @<name>@blank snapshotted back to @<name> yields a fresh writable subvol.
  #
  # run_latehook: `filesystems` has now mounted @ at /new_root, but the rollback
  # subvols are NOT mounted (only @ is — the nested subvols would otherwise
  # mount via fstab at local-fs.target, LONG after PID1 starts). Mount each
  # recreated subvol under /new_root here, before switch_root, so PID1 reads a
  # populated /etc (machine-id/hostname/localtime); otherwise every boot sees
  # the empty @/etc mountpoint, systemd-firstboot Initial Setup runs, and boot
  # hangs on the console prompt. This mirrors the archzfs hook mounting the
  # dataset hierarchy in the initramfs. systemd later adopts these
  # already-mounted paths from fstab.
  cat > "$hooks_directory/btrfs-rollback" <<HOOK
#!/usr/bin/ash
run_hook() {
  local subvols="$subvolume_list"
  local dev top sv
  dev="\$(resolve_device "\$(getarg root)")"
  top="/btrfs-rollback-top"
  mkdir -p "\$top"
  if ! mount -t btrfs -o subvolid=5 "\$dev" "\$top"; then
    err "impermanence: cannot mount btrfs top-level \$dev"
    launch_interactive_shell
  fi
  for sv in \$subvols; do
    if [ ! -e "\$top/\${sv}@blank" ]; then
      err "impermanence: @blank snapshot missing for \${sv}"
      launch_interactive_shell
    fi
    btrfs subvolume delete "\$top/\$sv"
    btrfs subvolume snapshot "\$top/\${sv}@blank" "\$top/\$sv"
  done
  umount "\$top"
}
run_latehook() {
  local pairs="$mountpoint_pairs"
  local dev pair sv mp
  dev="\$(resolve_device "\$(getarg root)")"
  for pair in \$pairs; do
    sv="\${pair%%:*}"
    mp="\${pair#*:}"
    mkdir -p "/new_root\$mp"
    if ! mount -t btrfs -o "subvol=\$sv" "\$dev" "/new_root\$mp"; then
      err "impermanence: cannot mount \$sv at /new_root\$mp"
      launch_interactive_shell
    fi
  done
}
HOOK
}

# FS-conditional PostTransaction resnapshot helper (ADR 0044). The pacman .hook
# is reused verbatim; only the script it execs differs — zfs destroys+snapshots
# each dataset @blank, btrfs deletes+re-snapshots each subvol @blank over the
# top-level mount.
impermanence_boot_hooks_write_resnapshot_helper() {
  if [[ "${FILESYSTEM:-zfs}" == "btrfs" ]]; then
    _impermanence_boot_hooks_write_resnapshot_helper_btrfs
  else
    _impermanence_boot_hooks_write_resnapshot_helper_zfs
  fi
}

_impermanence_boot_hooks_write_resnapshot_helper_zfs() {
  local directory="${ROOT:-}/usr/lib/impermanence"
  local file="$directory/resnapshot.sh"
  local entry suffix dataset_list=""
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    dataset_list+="$RPOOL/ROOT/$suffix "
  done
  dataset_list="${dataset_list% }"
  mkdir -p "$directory"
  cat > "$file" <<HELPER
#!/usr/bin/env bash
# Re-snapshot @blank on every Rollback Dataset after a pacman transaction.
# Idempotent: a missing @blank (destroy error) is ignored; the snapshot
# command then creates it fresh. Errors are logged but never abort —
# pacman has already succeeded by the time this hook fires.
#
# v1 leak: this script runs PostTransaction only. User edits to non-
# persisted paths made before a pacman run get baked into the new @blank
# and survive one extra reboot. The fix is a pre-transaction strict-mode
# hook with 'os impermanence diff/accept-drift/revert-drift' verbs,
# deferred to v2.
datasets="$dataset_list"
for ds in \$datasets; do
  if zfs destroy "\${ds}@blank" 2>/dev/null; then
    logger -t impermanence "destroyed \${ds}@blank"
  fi
  if zfs snapshot "\${ds}@blank"; then
    logger -t impermanence "snapshotted \${ds}@blank"
  else
    logger -t impermanence "FAILED snapshot \${ds}@blank"
  fi
done
HELPER
  chmod 0755 "$file"
}

_impermanence_boot_hooks_write_resnapshot_helper_btrfs() {
  local directory="${ROOT:-}/usr/lib/impermanence"
  local file="$directory/resnapshot.sh"
  local entry suffix subvolume_list=""
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    subvolume_list+="@$suffix "
  done
  subvolume_list="${subvolume_list% }"
  mkdir -p "$directory"
  cat > "$file" <<HELPER
#!/usr/bin/env bash
# Re-snapshot @blank on every rollback subvol after a pacman transaction.
# Idempotent: a missing @blank (delete error) is ignored; the snapshot then
# creates it fresh. Errors are logged but never abort — pacman has already
# succeeded by the time this hook fires. Operates over the btrfs top-level
# (subvolid=5), so it resolves the live root device and mounts it transiently.
#
# v1 leak: this script runs PostTransaction only. User edits to non-persisted
# paths made before a pacman run get baked into the new @blank and survive one
# extra reboot. The fix is a pre-transaction strict-mode hook with
# 'os impermanence diff/accept-drift/revert-drift' verbs, deferred to v2.
subvols="$subvolume_list"
dev="\$(findmnt -nro SOURCE --target / | sed 's/\[[^]]*\]\$//')"
top="\$(mktemp -d)"
if ! mount -o subvolid=5 "\$dev" "\$top"; then
  logger -t impermanence "FAILED to mount btrfs top-level \$dev"
  exit 0
fi
for sv in \$subvols; do
  if btrfs subvolume delete "\$top/\${sv}@blank" 2>/dev/null; then
    logger -t impermanence "deleted \${sv}@blank"
  fi
  if btrfs subvolume snapshot -r "\$top/\$sv" "\$top/\${sv}@blank"; then
    logger -t impermanence "snapshotted \${sv}@blank"
  else
    logger -t impermanence "FAILED snapshot \${sv}@blank"
  fi
done
umount "\$top"
rmdir "\$top" 2>/dev/null || true
HELPER
  chmod 0755 "$file"
}

impermanence_boot_hooks_write_resnapshot_hook() {
  local directory="${ROOT:-}/etc/pacman.d/hooks"
  mkdir -p "$directory"
  cat > "$directory/zz-impermanence-resnapshot.hook" <<'HOOK'
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Operation = Remove
Target = *

[Action]
Description = Re-snapshotting @blank on Rollback Datasets...
When = PostTransaction
Exec = /usr/lib/impermanence/resnapshot.sh
HOOK
}

