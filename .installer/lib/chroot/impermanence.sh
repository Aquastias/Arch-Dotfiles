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
# Like dirname: a path with no slash means the current directory.
_IMP_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_IMP_DIR" != "${BASH_SOURCE[0]}" ]] || _IMP_DIR=.
# parent_directory / base_name — the chroot-world path helpers (sibling).
# shellcheck source=./chroot-common.sh
declare -F parent_directory >/dev/null 2>&1 \
  || source "$_IMP_DIR/chroot-common.sh"
_IMP_COMMON="$_IMP_DIR/impermanence-common.sh"
[[ -f "$_IMP_COMMON" ]] || _IMP_COMMON="$_IMP_DIR/../impermanence-common.sh"
# shellcheck disable=SC1090
source "$_IMP_COMMON"
# The initramfs rollback hook + the pacman resnapshot helper/hook writers.
# shellcheck source=./impermanence-boot-hooks.sh
source "$_IMP_DIR/impermanence-boot-hooks.sh"

# Local logger — chroot scripts don't source lib/common.sh, and the unset
# `info` shadows by texinfo's /usr/bin/info, which fails under set -e.
info() { printf '[impermanence] %s\n' "$*" >&2; }

# The Persist Dataset (rpool/persist) AND the Rollback Datasets
# (rpool/ROOT/{etc,opt,root,srv,usrlocal}) are created EARLY, during
# pool/dataset creation, by impermanence_common_create_persist_dataset +
# impermanence_common_create_rollback_datasets (see lib/impermanence-common.sh). They must exist
# before pacstrap (so the OS populates the rollback datasets) and land in the
# zfs-list.cache (so they mount at boot — the Persist Dataset early enough that
# the curated Persist Mounts restore /etc state before dbus). This module only
# consumes them (stage curated dirs, snapshot @blank, write the rollback hook).

_impermanence_write_manifest() {
  local directory="${ROOT:-}/usr/lib/impermanence"
  mkdir -p "$directory"
  printf '%s\n' "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}" \
    | sort > "$directory/defaults.manifest"
}

_impermanence_apply_curated() {
  local units="${ROOT:-}/usr/lib/systemd/system"
  local wants="$units/local-fs.target.wants"
  local config_file="${ROOT:-}/usr/lib/tmpfiles.d/impermanence-curated.conf"
  mkdir -p "$(parent_directory "$config_file")"
  : > "$config_file"
  local target file_source file_destination
  # Curated DIRS hold mutable state — MOVE them onto the Persist Dataset so the
  # @blank snapshot is genuinely blank of them; a bind restores them at
  # local-fs.target.
  for target in "${CURATED_DIRS[@]}"; do
    impermanence_common_persist_apply "$target" d "$units" "$config_file"
    impermanence_common_link_wants "$target" "$wants"
    if [[ -e "${ROOT:-}$target" ]]; then
      impermanence_common_persist_stage_in_move "$target" "${ROOT:-}" "${ROOT:-}${IMPERMANENCE_MOUNT}"
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
    impermanence_common_persist_apply "$target" f "$units" "$config_file"
    impermanence_common_link_wants "$target" "$wants"
    file_source="${ROOT:-}$target"
    file_destination="${ROOT:-}${IMPERMANENCE_MOUNT}$target"
    if [[ -e "$file_source" ]]; then
      mkdir -p "$(parent_directory "$file_destination")"
      cp -a "$file_source" "$file_destination"
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
        || awk '{ gsub(/-/, ""); print }' /proc/sys/kernel/random/uuid; } \
      > "$mid" \
      || info "impermanence: failed to write /etc/machine-id"
  fi
}

# Units + wants go to /usr/lib like the curated ones: PID 1 plans boot before
# the /etc/systemd/system bootstrap bind, so /persist units never mount (ADR
# 0144). tmpfiles entries stay on /persist (tmpfiles runs after local-fs).
_impermanence_apply_extensions() {
  local units="${ROOT:-}/usr/lib/systemd/system"
  local wants="$units/local-fs.target.wants"
  local config_file="${ROOT:-}${IMPERMANENCE_MOUNT}/etc/tmpfiles.d"
  config_file+="/impermanence-extensions.conf"
  mkdir -p "$(parent_directory "$config_file")"
  : > "$config_file"
  local target
  for target in "${PERSIST_DIRECTORIES[@]:-}"; do
    [[ -z "$target" ]] && continue
    impermanence_common_persist_apply "$target" d "$units" "$config_file"
    impermanence_common_link_wants "$target" "$wants"
    if [[ -e "${ROOT:-}$target" ]]; then
      impermanence_common_persist_stage_in_move "$target" "${ROOT:-}" "${ROOT:-}${IMPERMANENCE_MOUNT}"
    else
      info "impermanence: skip missing extension source $target"
    fi
  done
  for target in "${PERSIST_FILES[@]:-}"; do
    [[ -z "$target" ]] && continue
    impermanence_common_persist_apply "$target" f "$units" "$config_file"
    impermanence_common_link_wants "$target" "$wants"
    if [[ -e "${ROOT:-}$target" ]]; then
      impermanence_common_persist_stage_in_move "$target" "${ROOT:-}" "${ROOT:-}${IMPERMANENCE_MOUNT}"
    else
      info "impermanence: skip missing extension source $target"
    fi
  done
}

# /etc/machine-id is a persist bind (a mount point), so the stock commit
# service runs and fails every boot; its id is already frozen in @blank.
_impermanence_skip_machine_id_commit() {
  local directory="${ROOT:-}/usr/lib/systemd/system"
  directory+="/systemd-machine-id-commit.service.d"
  mkdir -p "$directory"
  printf '[Unit]\nConditionPathIsMountPoint=!/etc/machine-id\n' \
    > "$directory/impermanence.conf"
}

_impermanence_write_bootstrap() {
  local directory="${ROOT:-}/usr/lib/tmpfiles.d"
  local file="$directory/impermanence-bootstrap.conf"
  local path bind_source bind_destination
  mkdir -p "$directory"
  : > "$file"
  for path in /etc/systemd/system /etc/tmpfiles.d; do
    printf "d %s 0755 root root - -\n" "$path" >> "$file"
    impermanence_common_write_mount_unit "$path"
    impermanence_common_link_wants "$path"
    # Stage the live content onto the Persist Dataset so the bind EXPOSES the
    # install-time service enablements (sops-runtime, sshd, … live as symlinks
    # in /etc/systemd/system/*.target.wants/). Without this the bind covers
    # /etc/systemd/system with an EMPTY /persist dir and every enabled service
    # vanishes at boot. COPY (not move) so @blank keeps them as a fallback.
    bind_source="${ROOT:-}$path"
    bind_destination="${ROOT:-}${IMPERMANENCE_MOUNT}$path"
    if [[ -d "$bind_source" ]]; then
      mkdir -p "$bind_destination"
      cp -a "$bind_source/." "$bind_destination/"
    fi
  done
}

# Resolve the device backing the btrfs root (/), stripping findmnt's
# `[/subvol]` suffix. Handles plaintext (the bare partition by UUID) and
# encrypted (/dev/mapper/cryptroot) uniformly. Used by the btrfs FS-layer to
# reach the top-level for subvolume snapshot/rollback.
_impermanence_btrfs_root_device() {
  findmnt -nro SOURCE --target "${ROOT:-/}" \
    | awk '{ sub(/\[[^]]*\]$/, ""); print }'
}

# ZFS @blank: a namespace snapshot per Rollback Dataset, no mount needed.
_impermanence_snapshot_blank_zfs() {
  local entry suffix
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    # shellcheck disable=SC2153  # RPOOL: install-state global (install-state.sh)
    zfs snapshot "$RPOOL/ROOT/$suffix@blank"
  done
}

# btrfs @blank: mount the top-level (subvolid=5) and take a read-only snapshot
# of each rollback subvol to a sibling `@<name>@blank` (ADR 0044). The boot
# rollback hook recreates @<name> from this. A subvolume snapshot needs both
# paths on a mounted btrfs, so the top-level mount is unavoidable here.
_impermanence_snapshot_blank_btrfs() {
  local top dev entry suffix
  dev="$(_impermanence_btrfs_root_device)"
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
# mirror units that ship a real file under /usr/lib/systemd/system (skips any
# operator unit that exists only under /etc).
_impermanence_relocate_enablements() {
  local sys="${ROOT:-}/usr/lib/systemd/system"
  local etc="${ROOT:-}/etc/systemd/system"
  [[ -d "$etc" ]] || return 0
  local wants target link unit
  for wants in "$etc"/*.target.wants; do
    [[ -d "$wants" ]] || continue
    target="$(base_name "$wants")"
    for link in "$wants"/*; do
      [[ -e "$link" || -L "$link" ]] || continue
      unit="$(base_name "$link")"
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
    local display_manager_unit
    display_manager_unit="$(readlink "$etc/display-manager.service")"
    ln -sf "$display_manager_unit" "$sys/display-manager.service"
  fi
}

# _impermanence_refresh_zfs_cache — regenerate the zfs-mount-generator cache
# into /etc IMMEDIATELY before @blank, so the rolled-back /etc always ships a
# COMPLETE cache. Without a full cache at early boot the generator emits no
# mount units and /var, /var/log mount late (via zfs-mount.service, AFTER
# systemd-journald starts) — which orphans the journal (journalctl shows
# nothing) and delays every early service touching /var. Reuses
# zfs_import_write_list_cache (canonical column order) from zfs-import.sh.
# zfs-only; a no-op on btrfs. Skips file-keyed encrypted DATA pools (their key
# isn't loaded when the generator runs).
_impermanence_refresh_zfs_cache() {
  [[ "${FILESYSTEM:-zfs}" == "zfs" ]] || return 0
  local zfs_import_lib="$_IMP_DIR/zfs-import.sh"
  if [[ ! -f "$zfs_import_lib" ]]; then
    info "impermanence: zfs-import.sh not found — skipping cache refresh"
    return 0
  fi
  # shellcheck source=./zfs-import.sh
  source "$zfs_import_lib"
  local directory="${ROOT:-}/etc/zfs/zfs-list.cache" pool key_location
  mkdir -p "$directory"
  for pool in $(zpool list -H -o name 2>/dev/null); do
    key_location="$(zfs get -H -o value keylocation "$pool" 2>/dev/null)"
    [[ "$key_location" == file://* ]] && continue
    zfs_import_write_list_cache "$pool" "$directory"
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
  local linger="$root/var/lib/systemd/linger" user
  mkdir -p "$linger"
  for user in "${humans[@]+"${humans[@]}"}"; do touch "$linger/$user"; done

  # (2) XDG_RUNTIME_DIR fallback for DM sessions started via a login shell.
  local profile_directory="$root/etc/profile.d"
  mkdir -p "$profile_directory"
  cat > "$profile_directory/10-impermanence-xdg-runtime.sh" <<'SH'
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
    _impermanence_skip_machine_id_commit \
    _impermanence_relocate_enablements \
    _impermanence_apply_curated \
    _impermanence_write_bootstrap \
    _impermanence_apply_extensions \
    impermanence_boot_hooks_write_rollback \
    impermanence_boot_hooks_write_resnapshot_hook \
    impermanence_boot_hooks_write_resnapshot_helper \
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
  # Like dirname: a path with no slash means the current directory.
  _LIB_DIR="${BASH_SOURCE[0]%/*}"
  [[ "$_LIB_DIR" != "${BASH_SOURCE[0]}" ]] || _LIB_DIR=.
  _INSTALL_STATE_SH="$_LIB_DIR/install-state.sh"
  [[ -f "$_INSTALL_STATE_SH" ]] || _INSTALL_STATE_SH="$_LIB_DIR/../install-state.sh"
  # shellcheck disable=SC1090
  source "$_INSTALL_STATE_SH"
  install_state_load "$STATE"
  set -Eeuo pipefail
  _impermanence_on_error() {
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
  trap '_impermanence_on_error $LINENO' ERR
  [[ "${IMP_DEBUG:-0}" == "1" ]] && set -x
  impermanence_apply
fi
