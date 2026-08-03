#!/usr/bin/env bash
# lib/chroot/impermanence.sh — Chroot Configuration Module for impermanence.
# Creates Persist + Rollback Datasets, generates bootstrap + curated mount
# units, takes @blank snapshots. No-op when IMPERMANENCE_ENABLED!=true.
#
# All file writes are rooted at ${ROOT:-} so tests can redirect under a
# temp dir. Production callers leave ROOT unset (writes to / inside chroot).

# Curated Persist Defaults + writers come from the shared common lib.
# Chroot stages it as sibling; source tree has it one level up.
# shellcheck source=../impermanence-common.sh
_IMP_DIR="$(dirname "${BASH_SOURCE[0]}")"
_IMP_COMMON="$_IMP_DIR/impermanence-common.sh"
[[ -f "$_IMP_COMMON" ]] || _IMP_COMMON="$_IMP_DIR/../impermanence-common.sh"
# shellcheck disable=SC1090
source "$_IMP_COMMON"

# Local logger — chroot scripts don't source lib/common.sh, and the unset
# `info` shadows by texinfo's /usr/bin/info, which fails under set -e.
info() { printf '[impermanence] %s\n' "$*" >&2; }

# The Persist Dataset (rpool/persist) AND the Rollback Datasets
# (rpool/ROOT/{etc,opt,root,srv,usrlocal}) are created EARLY, during
# pool/dataset creation, by imp_create_persist_dataset +
# imp_create_rollback_datasets (see lib/impermanence-common.sh). They must exist
# before pacstrap (so the OS populates the rollback datasets) and land in the
# zfs-list.cache (so they mount at boot — the Persist Dataset early enough that
# the curated Persist Mounts restore /etc state before dbus). This module only
# consumes them (stage curated dirs, snapshot @blank, write the rollback hook).

_impermanence_write_manifest() {
  local dir="${ROOT:-}/usr/lib/impermanence"
  mkdir -p "$dir"
  printf '%s\n' "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}" \
    | sort > "$dir/defaults.manifest"
}

_impermanence_apply_curated() {
  local units="${ROOT:-}/usr/lib/systemd/system"
  local wants="$units/local-fs.target.wants"
  local conf="${ROOT:-}/usr/lib/tmpfiles.d/impermanence-curated.conf"
  mkdir -p "$(dirname "$conf")"
  : > "$conf"
  local target fsrc fdst
  # Curated DIRS hold mutable state — MOVE them onto the Persist Dataset so the
  # @blank snapshot is genuinely blank of them; a bind restores them at
  # local-fs.target.
  for target in "${CURATED_DIRS[@]}"; do
    persist_apply "$target" d "$units" "$conf"
    imp_link_wants "$target" "$wants"
    if [[ -e "${ROOT:-}$target" ]]; then
      persist_stage_in_move "$target" "${ROOT:-}" "${ROOT:-}${IMPERMANENCE_MOUNT}"
    else
      info "impermanence: skip missing curated source $target"
    fi
  done
  # Curated FILES (machine-id, hostname, locale.conf, vconsole.conf, fstab,
  # adjtime) are read by PID 1 / generators BEFORE any .mount unit, so a
  # /persist bind restores them too late — an empty /etc/machine-id after the
  # @blank rollback makes systemd treat every boot as the first boot
  # (systemd-firstboot + dbus thrash) and an empty /etc/fstab loses early
  # mounts. COPY them (keep the source) so they stay in /etc and @blank captures
  # real, frozen-at-install values. The bind unit is still written — a harmless
  # redundant overlay of the identical value.
  for target in "${CURATED_FILES[@]}"; do
    persist_apply "$target" f "$units" "$conf"
    imp_link_wants "$target" "$wants"
    fsrc="${ROOT:-}$target"; fdst="${ROOT:-}${IMPERMANENCE_MOUNT}$target"
    if [[ -e "$fsrc" ]]; then
      mkdir -p "$(dirname "$fdst")"
      cp -a "$fsrc" "$fdst"
    else
      info "impermanence: skip missing curated source $target"
    fi
  done
}

# Initialise /etc/machine-id with a real value BEFORE @blank. A chroot install
# leaves it empty (systemd defers it to first boot); if @blank captured an empty
# machine-id the rollback would re-empty it every boot. machine-id is read by
# PID 1 before any .mount unit, so it must live populated in the rolled-back
# dataset's @blank, not be restored from /persist.
#
# systemd-machine-id-setup in a chroot often writes NOTHING or the literal
# `uninitialized` marker (it defers real generation to first boot). That is fatal
# here: PID 1 then mints a fresh TRANSIENT id every boot, and dbus-broker /
# systemd --user / logind all key off the machine-id — an unstable id breaks the
# graphical session (no XDG_RUNTIME_DIR → kwin_wayland "Could not create wayland
# socket" → black screen). So verify a committed 32-hex id actually landed; if
# not, mint one explicitly so @blank freezes a stable value.
_impermanence_init_machine_id() {
  local mid="${ROOT:-}/etc/machine-id"
  systemd-machine-id-setup --root="${ROOT:-/}" >/dev/null 2>&1 || true
  if ! grep -qE '^[0-9a-f]{32}$' "$mid" 2>/dev/null; then
    info "impermanence: /etc/machine-id empty/uninitialized — generating one"
    { systemd-id128 new 2>/dev/null \
        || tr -d '-' < /proc/sys/kernel/random/uuid; } > "$mid" \
      || info "impermanence: failed to write /etc/machine-id"
  fi
}

_impermanence_apply_extensions() {
  local units="${ROOT:-}${IMPERMANENCE_MOUNT}/etc/systemd/system"
  local wants="$units/local-fs.target.wants"
  local conf="${ROOT:-}${IMPERMANENCE_MOUNT}/etc/tmpfiles.d/impermanence-extensions.conf"
  mkdir -p "$(dirname "$conf")"
  : > "$conf"
  local target
  for target in "${PERSIST_DIRECTORIES[@]:-}"; do
    [[ -z "$target" ]] && continue
    persist_apply "$target" d "$units" "$conf"
    imp_link_wants "$target" "$wants"
    if [[ -e "${ROOT:-}$target" ]]; then
      persist_stage_in_move "$target" "${ROOT:-}" "${ROOT:-}${IMPERMANENCE_MOUNT}"
    else
      info "impermanence: skip missing extension source $target"
    fi
  done
  for target in "${PERSIST_FILES[@]:-}"; do
    [[ -z "$target" ]] && continue
    persist_apply "$target" f "$units" "$conf"
    imp_link_wants "$target" "$wants"
    if [[ -e "${ROOT:-}$target" ]]; then
      persist_stage_in_move "$target" "${ROOT:-}" "${ROOT:-}${IMPERMANENCE_MOUNT}"
    else
      info "impermanence: skip missing extension source $target"
    fi
  done
}

_impermanence_write_bootstrap() {
  local dir="${ROOT:-}/usr/lib/tmpfiles.d"
  local f="$dir/impermanence-bootstrap.conf"
  local p bsrc bdst
  mkdir -p "$dir"
  : > "$f"
  for p in /etc/systemd/system /etc/tmpfiles.d; do
    printf "d %s 0755 root root - -\n" "$p" >> "$f"
    imp_write_mount_unit "$p"
    imp_link_wants "$p"
    # Stage the live content onto the Persist Dataset so the bind EXPOSES the
    # install-time service enablements (sops-runtime, sshd, … live as symlinks
    # in /etc/systemd/system/*.target.wants/). Without this the bind covers
    # /etc/systemd/system with an EMPTY /persist dir and every enabled service
    # vanishes at boot. COPY (not move) so @blank keeps them as a fallback.
    bsrc="${ROOT:-}$p"; bdst="${ROOT:-}${IMPERMANENCE_MOUNT}$p"
    if [[ -d "$bsrc" ]]; then
      mkdir -p "$bdst"
      cp -a "$bsrc/." "$bdst/"
    fi
  done
}

# Resolve the device backing the btrfs root (/), stripping findmnt's
# `[/subvol]` suffix. Handles plaintext (the bare partition by UUID) and
# encrypted (/dev/mapper/cryptroot) uniformly. Used by the btrfs FS-layer to
# reach the top-level for subvolume snapshot/rollback.
_imp_btrfs_root_dev() {
  findmnt -nro SOURCE --target "${ROOT:-/}" | sed 's/\[[^]]*\]$//'
}

# ZFS @blank: a namespace snapshot per Rollback Dataset, no mount needed.
_impermanence_snapshot_blank_zfs() {
  local entry suffix
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    zfs snapshot "$RPOOL/ROOT/$suffix@blank"
  done
}

# btrfs @blank: mount the top-level (subvolid=5) and take a read-only snapshot
# of each rollback subvol to a sibling `@<name>@blank` (ADR 0044). The boot
# rollback hook recreates @<name> from this. A subvolume snapshot needs both
# paths on a mounted btrfs, so the top-level mount is unavoidable here.
_impermanence_snapshot_blank_btrfs() {
  local top dev entry suffix
  dev="$(_imp_btrfs_root_dev)"
  top="$(mktemp -d)"
  mount -o subvolid=5 "$dev" "$top"
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    btrfs subvolume snapshot -r "$top/@$suffix" "$top/@$suffix@blank"
  done
  umount "$top"
  rmdir "$top"
}

# FS-conditional @blank (ADR 0044): swap the snapshot primitive, nothing else.
_impermanence_snapshot_blank() {
  if [[ "${FILESYSTEM:-zfs}" == "btrfs" ]]; then
    _impermanence_snapshot_blank_btrfs
  else
    _impermanence_snapshot_blank_zfs
  fi
}

# FS-conditional rollback hook (ADR 0044): write the zfs-rollback or the
# btrfs-rollback initramfs hook. Both honour the same contract — roll every
# curated path back to its @blank on boot, failing closed to an emergency shell
# on a missing @blank. The HOOKS list (the Root Adapter) names the matching hook.
_impermanence_write_rollback_hook() {
  if [[ "${FILESYSTEM:-zfs}" == "btrfs" ]]; then
    _impermanence_write_rollback_hook_btrfs
  else
    _impermanence_write_rollback_hook_zfs
  fi
}

_impermanence_write_rollback_hook_zfs() {
  local idir="${ROOT:-}/usr/lib/initcpio/install"
  local hdir="${ROOT:-}/usr/lib/initcpio/hooks"
  mkdir -p "$idir" "$hdir"

  cat > "$idir/zfs-rollback" <<'INSTALL'
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
  local entry suffix mp ds_list="" mount_pairs=""
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    mp="${entry#*:}"
    ds_list+="$RPOOL/ROOT/$suffix "
    mount_pairs+="$RPOOL/ROOT/$suffix=$mp "
  done
  ds_list="${ds_list% }"
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
  cat > "$hdir/zfs-rollback" <<HOOK
#!/usr/bin/ash
run_latehook() {
  local datasets="$ds_list"
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

_impermanence_write_rollback_hook_btrfs() {
  local idir="${ROOT:-}/usr/lib/initcpio/install"
  local hdir="${ROOT:-}/usr/lib/initcpio/hooks"
  mkdir -p "$idir" "$hdir"

  cat > "$idir/btrfs-rollback" <<'INSTALL'
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
  local entry suffix mp sv_list="" mp_pairs=""
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    mp="${entry#*:}"
    sv_list+="@$suffix "
    mp_pairs+="@$suffix:$mp "
  done
  sv_list="${sv_list% }"
  mp_pairs="${mp_pairs% }"

  # run_hook (not latehook): reset the subvols on the btrfs top-level before
  # `filesystems` pivots into the root. The kernel root= device is resolved with
  # the stock initcpio resolve_device/getarg helpers (handles UUID= plaintext and
  # the /dev/mapper/cryptroot the encrypt hook already opened). A read-only
  # @<name>@blank snapshotted back to @<name> yields a fresh writable subvol.
  #
  # run_latehook: `filesystems` has now mounted @ at /new_root, but the rollback
  # subvols are NOT mounted (only @ is — the nested subvols would otherwise mount
  # via fstab at local-fs.target, LONG after PID1 starts). Mount each recreated
  # subvol under /new_root here, before switch_root, so PID1 reads a populated
  # /etc (machine-id/hostname/localtime); otherwise every boot sees the empty
  # @/etc mountpoint, systemd-firstboot Initial Setup runs, and boot hangs on the
  # console prompt. This mirrors the archzfs hook mounting the dataset hierarchy
  # in the initramfs. systemd later adopts these already-mounted paths from fstab.
  cat > "$hdir/btrfs-rollback" <<HOOK
#!/usr/bin/ash
run_hook() {
  local subvols="$sv_list"
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
  local pairs="$mp_pairs"
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
_impermanence_write_resnapshot_helper() {
  if [[ "${FILESYSTEM:-zfs}" == "btrfs" ]]; then
    _impermanence_write_resnapshot_helper_btrfs
  else
    _impermanence_write_resnapshot_helper_zfs
  fi
}

_impermanence_write_resnapshot_helper_zfs() {
  local dir="${ROOT:-}/usr/lib/impermanence"
  local f="$dir/resnapshot.sh"
  local entry suffix ds_list=""
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    ds_list+="$RPOOL/ROOT/$suffix "
  done
  ds_list="${ds_list% }"
  mkdir -p "$dir"
  cat > "$f" <<HELPER
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
datasets="$ds_list"
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
  chmod 0755 "$f"
}

_impermanence_write_resnapshot_helper_btrfs() {
  local dir="${ROOT:-}/usr/lib/impermanence"
  local f="$dir/resnapshot.sh"
  local entry suffix sv_list=""
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    sv_list+="@$suffix "
  done
  sv_list="${sv_list% }"
  mkdir -p "$dir"
  cat > "$f" <<HELPER
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
subvols="$sv_list"
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
  chmod 0755 "$f"
}

_impermanence_write_resnapshot_hook() {
  local dir="${ROOT:-}/etc/pacman.d/hooks"
  mkdir -p "$dir"
  cat > "$dir/zz-impermanence-resnapshot.hook" <<'HOOK'
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

# Mirror install-time `systemctl enable` results onto the never-rolled-back
# /usr/lib tree. `systemctl enable` writes wants-symlinks into
# /etc/systemd/system/<target>.wants/ and the display-manager.service alias into
# /etc/systemd/system/. Under impermanence /etc rolls back to @blank and the
# persist bind lands only at local-fs.target — too late for PID1's INITIAL boot
# transaction — so those /etc enablements are invisible when systemd decides what
# to start, and the services silently never autostart (NetworkManager, sddm, …).
# The test harness's own boot sentinel already relies on this asymmetry
# ([[impermanence-service-enable]]): a wants-symlink under
# /usr/lib/systemd/system/<target>.wants/ IS honoured (that tree lives on the
# root dataset, never a Rollback Dataset, present from PID1 start), while the
# /etc one is not. So mirror every install-time enablement onto /usr/lib. COPY
# (leave the /etc symlinks in place) — the persist bind still exposes them
# post-boot; the /usr copy is what the boot transaction actually honours. Only
# mirror units that ship a real file under /usr/lib/systemd/system (skips
# impermanence's own local-fs.target.wants/*.mount, whose units live on the
# Persist Dataset, and any operator unit that exists only under /etc).
_impermanence_relocate_enablements() {
  local sys="${ROOT:-}/usr/lib/systemd/system"
  local etc="${ROOT:-}/etc/systemd/system"
  [[ -d "$etc" ]] || return 0
  local wants target link unit
  for wants in "$etc"/*.target.wants; do
    [[ -d "$wants" ]] || continue
    target="$(basename "$wants")"
    for link in "$wants"/*; do
      [[ -e "$link" || -L "$link" ]] || continue
      unit="$(basename "$link")"
      [[ -e "$sys/$unit" ]] || continue     # packaged units only
      mkdir -p "$sys/$target"
      ln -sf "../$unit" "$sys/$target/$unit"
    done
  done
  # The display-manager.service alias (created by `systemctl enable <dm>`):
  # graphical.target ships Wants=display-manager.service, but the alias symlink
  # lives in /etc and won't resolve at boot. Mirror it onto /usr/lib so the DM
  # (sddm) autostarts. readlink yields the absolute DM unit path.
  if [[ -L "$etc/display-manager.service" ]]; then
    local dm; dm="$(readlink "$etc/display-manager.service")"
    ln -sf "$dm" "$sys/display-manager.service"
  fi
}

# _impermanence_refresh_zfs_cache — regenerate the zfs-mount-generator cache into
# /etc IMMEDIATELY before @blank, so the rolled-back /etc always ships a COMPLETE
# cache. Without a full cache at early boot the generator emits no mount units and
# /var, /var/log mount late (via zfs-mount.service, AFTER systemd-journald starts)
# — which orphans the journal (journalctl shows nothing) and delays every early
# service touching /var. Reuses zfs_write_list_cache (canonical column order) from
# zfs-import.sh. zfs-only; a no-op on btrfs. Skips file-keyed encrypted DATA pools
# (their key isn't loaded when the generator runs).
_impermanence_refresh_zfs_cache() {
  [[ "${FILESYSTEM:-zfs}" == "zfs" ]] || return 0
  local zi="$_IMP_DIR/zfs-import.sh"
  if [[ ! -f "$zi" ]]; then
    info "impermanence: zfs-import.sh not found — skipping cache refresh"
    return 0
  fi
  # shellcheck source=./zfs-import.sh
  source "$zi"
  local dir="${ROOT:-}/etc/zfs/zfs-list.cache" p kl
  mkdir -p "$dir"
  for p in $(zpool list -H -o name 2>/dev/null); do
    kl="$(zfs get -H -o value keylocation "$p" 2>/dev/null)"
    [[ "$kl" == file://* ]] && continue
    zfs_write_list_cache "$p" "$dir"
  done
}

# _impermanence_graphical_session_fix — make the graphical user session survive
# impermanence. On a rolled-back root the display manager logs a user in
# at boot BEFORE logind/pam_systemd can register the session against the freshly
# mounted ZFS datasets: no session is created, so XDG_RUNTIME_DIR is unset,
# /run/user/$uid + its D-Bus socket never appear, and kwin_wayland dies with
# "Could not create wayland socket" → black screen. A later TTY login works
# (system settled), which is the tell. A non-impermanent install never races, so
# it logs in fine. The display manager is kept (a real login screen on every
# host, ADR 0061); these three make the DM-initiated user session bullet-proof
# on a rolled-back root, none needed without impermanence:
#
#   1. enable-linger per human user — a marker on the persistent /var dataset
#      (rpool/var, never rolled back) so logind keeps user@$uid around.
#   2. An /etc/profile.d XDG_RUNTIME_DIR fallback — if the DM runs the session
#      through a login shell it sources /etc/profile.d, so this lands in the
#      session env and points kwin at the lingering /run/user/$uid when
#      pam_systemd didn't export it. Harmless when already set / not sourced.
#      Written to /etc so @blank captures it.
#   3. A oneshot that explicitly starts user@$uid BEFORE the greeter. The (1)
#      marker only fires if logind reads it after /var is mounted, but /var is a
#      late ZFS mount so that read can miss it: user@ never starts, login then
#      block-starts the manager, and pam_systemd times out on a busy boot (no
#      XDG_RUNTIME_DIR, black screen). Ordered After=systemd-logind +
#      local-fs.target (both up, /var mounted) and pulled into multi-user.target
#      (before the greeter); it does NOT order logind itself (that risks an
#      ordering cycle that blacks the greeter). Unit + wants-symlink live on
#      /usr (never rolled back, honoured by PID1's initial boot transaction).
_impermanence_graphical_session_fix() {
  local root="${ROOT:-}"

  # Human users (uid 1000..65533), collected once.
  local humans=() name uid
  if [[ -f "$root/etc/passwd" ]]; then
    while IFS=: read -r name _ uid _; do
      [[ "$uid" =~ ^[0-9]+$ ]] || continue
      (( uid >= 1000 && uid < 65534 )) || continue
      humans+=("$name")
    done < "$root/etc/passwd"
  fi

  # (1) linger markers.
  local linger="$root/var/lib/systemd/linger" u
  mkdir -p "$linger"
  for u in "${humans[@]+"${humans[@]}"}"; do touch "$linger/$u"; done

  # (2) XDG_RUNTIME_DIR fallback for DM sessions started via a login shell.
  local pd="$root/etc/profile.d"
  mkdir -p "$pd"
  cat > "$pd/10-impermanence-xdg-runtime.sh" <<'SH'
# Impermanence: if the display manager starts the session through a login shell,
# and pam_systemd failed to export XDG_RUNTIME_DIR at graphical login (logind
# session race on the rolled-back root), point it at the lingering runtime dir
# so kwin_wayland can create its wayland socket. Harmless when already set.
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
  _imp_uid="$(id -u 2>/dev/null || true)"
  if [ -n "$_imp_uid" ] && [ -d "/run/user/$_imp_uid" ]; then
    export XDG_RUNTIME_DIR="/run/user/$_imp_uid"
  fi
  unset _imp_uid
fi
SH

  # (3) Boot oneshot that starts each human user's manager before the greeter.
  if ((${#humans[@]})); then
    local sysd="$root/usr/lib/systemd/system"
    mkdir -p "$sysd/multi-user.target.wants"
    cat > "$sysd/impermanence-user-linger.service" <<UNIT
[Unit]
Description=Start lingering user managers before the greeter (impermanence)
# /var (the linger markers) must be mounted and logind up; do NOT order logind
# itself After a mount (risks a boot ordering cycle that blacks the greeter).
After=systemd-logind.service local-fs.target
Wants=systemd-logind.service

[Service]
Type=oneshot
RemainAfterExit=yes
# enable-linger persists the marker and starts user@\$uid now (runtime dir +
# user D-Bus + systemd --user), so the login just attaches instead of block-
# starting the manager (which times out during a busy boot).
ExecStart=/usr/bin/loginctl enable-linger ${humans[*]}

[Install]
WantedBy=multi-user.target
UNIT
    ln -sf ../impermanence-user-linger.service \
      "$sysd/multi-user.target.wants/impermanence-user-linger.service"
  fi
}

impermanence_apply() {
  [[ "${IMPERMANENCE_ENABLED:-false}" == "true" ]] || return 0
  local step
  for step in \
    _impermanence_write_manifest \
    _impermanence_init_machine_id \
    _impermanence_relocate_enablements \
    _impermanence_apply_curated \
    _impermanence_write_bootstrap \
    _impermanence_apply_extensions \
    _impermanence_write_rollback_hook \
    _impermanence_write_resnapshot_hook \
    _impermanence_write_resnapshot_helper \
    _impermanence_refresh_zfs_cache \
    _impermanence_graphical_session_fix \
    _impermanence_snapshot_blank
  do
    info "step: $step"
    "$step"
  done
}

# When invoked as a script (not sourced), load state and apply.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # shellcheck source=./install-state.sh
  STATE="${STATE:-/root/lib-chroot/install-state.json}"
  _LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
  _INSTALL_STATE_SH="$_LIB_DIR/install-state.sh"
  [[ -f "$_INSTALL_STATE_SH" ]] || _INSTALL_STATE_SH="$_LIB_DIR/../install-state.sh"
  # shellcheck disable=SC1090
  source "$_INSTALL_STATE_SH"
  install_state_load "$STATE"
  set -Eeuo pipefail
  _imp_on_err() {
    local rc=$? lineno=$1
    {
      echo "[chroot:impermanence] FAILED"
      echo "  line:    $lineno"
      echo "  command: $BASH_COMMAND"
      echo "  funcs:   ${FUNCNAME[*]:1}"
      echo "  rc:      $rc"
    } >&2
    exit "$rc"
  }
  trap '_imp_on_err $LINENO' ERR
  [[ "${IMP_DEBUG:-0}" == "1" ]] && set -x
  impermanence_apply
fi
