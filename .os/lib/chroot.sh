#!/usr/bin/env bash
# =============================================================================
# lib/chroot.sh — System configuration inside arch-chroot
# =============================================================================
# Sourced by 03-install.sh.
# Requires: lib/common.sh and lib/install-state.sh already sourced.
#
# Provides:
#   write_fstab           — writes /etc/fstab from LAYOUT_ESP_PARTS (1+ ESPs)
#   write_esp_mirror_hook — installs a pacman hook that syncs secondary ESPs
#   configure_system — seeds ZFS state, then runs the full chroot
#                      configuration
#
# configure_system stages lib/chroot/ as /root/lib-chroot/ in the new root,
# delegates install-state.json writing to install_state_write, passes ROOT_PW
# via env var, then runs /root/lib-chroot/configure.sh.
# =============================================================================

# =============================================================================
# FSTAB WRITERS
# =============================================================================

# Pure fstab generator — no I/O. Args: one or more UUID strings (primary first).
# Returns fstab content on stdout. Test seam: call directly with fake UUIDs.
_chroot_fstab_generate() {
  (($# >= 1)) || {
    echo "_chroot_fstab_generate: no UUIDs provided" >&2
    return 1
  }
  local -a uuids=("$@")
  local count="${#uuids[@]}"
  if ((count == 1)); then
    echo "# EFI System Partition"
    echo "UUID=${uuids[0]}  /boot/efi  vfat  umask=0077  0 2"
  else
    echo "# EFI System Partition — primary"
    echo "UUID=${uuids[0]}  /boot/efi  vfat  umask=0077  0 2"
    local i
    for i in $(seq 1 $((count - 1))); do
      echo ""
      echo "# EFI System Partition — secondary ${i}" \
           "(kept in sync by pacman hook)"
      echo "UUID=${uuids[$i]}  /boot/efi${i}  vfat  umask=0077  0 2"
    done
  fi
  echo ""
  echo "# ZFS datasets are auto-mounted by zfs-mount-generator"
}

# Resolves UUIDs from LAYOUT_ESP_PARTS via blkid, delegates to
# _chroot_fstab_generate,
# writes result to ${MOUNT_ROOT}/etc/fstab.
write_fstab() {
  local count="${#LAYOUT_ESP_PARTS[@]}"
  ((count >= 1)) || error "write_fstab: LAYOUT_ESP_PARTS is empty."
  local -a uuids=()
  local part
  for part in "${LAYOUT_ESP_PARTS[@]}"; do
    uuids+=("$(blkid -s UUID -o value "$part")")
  done
  _chroot_fstab_generate "${uuids[@]}" >"${MOUNT_ROOT}/etc/fstab"
  info "fstab written (${count} ESP(s))."
}

# =============================================================================
# ESP MIRROR PACMAN HOOK
# =============================================================================

write_esp_mirror_hook() {
  # Installs a pacman hook that rsyncs the primary ESP (/boot/efi) to all
  # secondary ESPs (/boot/efi1, /boot/efi2, ...) after every kernel update
  # or systemd-boot update. This keeps every OS disk independently bootable.
  #
  # The hook fires on any change to:
  #   usr/lib/modules/*/vmlinuz  — kernel image updated
  #   usr/lib/systemd/boot/efi/*.efi  — systemd-boot EFI binary updated

  local esp_count="$1"
  # Explicit `return 0`: bare `return` would propagate the false-arithmetic
  # exit status from `((esp_count > 1))`, tripping the ERR trap one frame up.
  ((esp_count > 1)) || return 0

  # alpm-hooks Exec must be a single line — no backslash continuation.
  # Keep logic in a script so the hook stays declarative.
  mkdir -p "${MOUNT_ROOT}/usr/local/sbin"
  cat >"${MOUNT_ROOT}/usr/local/sbin/esp-mirror" <<'SCRIPT'
#!/usr/bin/bash
set -euo pipefail
for d in /boot/efi*/; do
  [[ "$d" != "/boot/efi/" ]] || continue
  rsync -a --delete /boot/efi/ "$d"
done
SCRIPT
  chmod 755 "${MOUNT_ROOT}/usr/local/sbin/esp-mirror"

  mkdir -p "${MOUNT_ROOT}/etc/pacman.d/hooks"
  cat >"${MOUNT_ROOT}/etc/pacman.d/hooks/95-esp-mirror.hook" <<'HOOK'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz
Target = usr/lib/systemd/boot/efi/*.efi

[Action]
Description = Mirroring ESP to secondary OS disks...
When = PostTransaction
Exec = /usr/local/sbin/esp-mirror
HOOK
  info "ESP mirror pacman hook installed."

  # Install paccache cleanup hook — runs after every pacman transaction
  # and keeps only the 2 most recent versions of each package in cache.
  # This prevents /var/cache/pacman/pkg from growing unbounded after updates.
  mkdir -p "${MOUNT_ROOT}/etc/pacman.d/hooks"
  cat >"${MOUNT_ROOT}/etc/pacman.d/hooks/90-paccache.hook" <<'HOOK'
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Cleaning pacman cache (keeping last 2 versions)...
When = PostTransaction
Exec = /usr/bin/paccache -rk2 --noconfirm
HOOK
  info "paccache auto-cleanup hook installed."
}

# =============================================================================
# CHROOT CONFIGURATION
# =============================================================================

collect_passwords() {
  # Collects the root password interactively on the LIVE ISO terminal (before
  # entering the chroot where stdin is bound to the heredoc).
  # Returns a compact JSON object: {"root":"pw"}.
  # User passwords are handled by the profiles runner with a default password.
  local result='{}'

  _prompt_password() {
    local label="$1"
    local pw1 pw2
    while true; do
      read -rsp "  Password for ${label}: " pw1 </dev/tty
      echo >&2
      read -rsp "  Confirm for ${label}: " pw2 </dev/tty
      echo >&2
      if [[ -z "$pw1" ]]; then
        echo "  Cannot be empty — try again." >&2
        continue
      fi
      if [[ "$pw1" != "$pw2" ]]; then
        echo "  Passwords do not match — try again." >&2
        continue
      fi
      printf '%s' "$pw1"
      return
    done
  }

  if [[ "${INSTALL_UNATTENDED:-0}" == "1" ]]; then
    # Default per CONTEXT.md: user passwords are hardcoded to "12345".
    # Root follows the same convention in unattended mode so the test
    # harness never blocks on a password prompt. Treat all installs from
    # this path as throwaway — change the password on first boot.
    info "Unattended mode — using default root password '12345'." >&2
    result="$(printf '%s' "$result" | jq --arg pw "12345" '. + {root: $pw}')"
    printf '%s' "$result"
    return
  fi

  echo "" >&2
  echo "━━━  Set root password  ━━━" >&2
  echo "" >&2

  local root_pw
  root_pw="$(_prompt_password "root")"
  result="$(printf '%s' "$result" | jq --arg pw "$root_pw" '. + {root: $pw}')"
  printf '%s' "$result"
}

_chroot_resolve_host_secrets() {
  local host_state="${MOUNT_ROOT}/install-state.json"
  [[ -f "$host_state" ]] || return 0
  local raw_path
  # SOPS-decrypted secrets (.secrets.host) or the Guided Installer's no-SOPS
  # passwords (.guided_passwords.host, issue 07) — same file shape, but the
  # guided key does not gate SOPS-program activation (ADR 0025).
  raw_path="$(jq -r \
    '.secrets.host // .guided_passwords.host // empty' "$host_state")"
  [[ -n "$raw_path" && -f "$raw_path" ]] || return 0
  cp "$raw_path" "${MOUNT_ROOT}/root/lib-chroot/host-secrets.json"
  printf '%s' "/root/lib-chroot/host-secrets.json"
}

# Seed a valid zpool.cache into the new root's /etc/zfs so the initramfs ZFS
# hook imports every pool at boot. `zpool set` takes exactly ONE pool per call
# — passing all pools at once (single-disk makes rpool AND dpool) made it fail,
# and the old `cp` fallback then copied the live ISO's stale/empty zpool.cache,
# baking a corrupt cache into the initramfs (boot died in a retry loop with
# "invalid or corrupt cache file"). Loop one pool per call so all land in one
# valid file. If any set fails or the file ends up empty, remove it entirely so
# the hook falls back to scan import (what the VMs did, hence they booted).
_chroot_seed_zpool_cache() {
  local cache="$1"; shift
  local p
  mkdir -p "$(dirname "$cache")"
  for p in "$@"; do
    if ! zpool set cachefile="$cache" "$p" 2>/dev/null; then
      rm -f "$cache"
      warn "zpool.cache could not be written for '$p' —" \
           "zfs-import-scan will handle first boot."
      return 0
    fi
  done
  if [[ ! -s "$cache" ]]; then
    rm -f "$cache"
    warn "zpool.cache is empty — zfs-import-scan will handle first boot."
    return 0
  fi
  info "Seeded zpool.cache with: $*"
}

configure_system() {
  section "Configuring System (arch-chroot)"

  # ── Seed ZFS state into the new root ──────────────────────────────────────
  # The pool cache and hostid must exist in the new system before the
  # initramfs is built, otherwise the ZFS hook cannot import the pool at boot.
  local _pools=()
  mapfile -t _pools < <(zpool list -H -o name)
  _chroot_seed_zpool_cache "${MOUNT_ROOT}/etc/zfs/zpool.cache" "${_pools[@]}"
  cp /etc/hostid "${MOUNT_ROOT}/etc/hostid"

  # Copy archzfs repo config so the new system can update ZFS packages
  cp /etc/pacman.conf "${MOUNT_ROOT}/etc/pacman.conf"

  # ── Copy extras/ scripts for execution inside chroot ──────────────────────
  if [[ -d "${SCRIPT_DIR}/extras" ]]; then
    # Remove any previous copy first so cp -r is always idempotent.
    # Without rm: if /root/extras already exists, cp -r would nest the
    # contents inside /root/extras/extras/ instead of /root/extras/.
    rm -rf "${MOUNT_ROOT}/root/extras"
    cp -r "${SCRIPT_DIR}/extras" "${MOUNT_ROOT}/root/extras"
    # Copy lib helpers so extras scripts can source jsonc(), extras-common, etc.
    mkdir -p "${MOUNT_ROOT}/root/lib"
    cp "${SCRIPT_DIR}/lib/common.sh"   "${MOUNT_ROOT}/root/lib/common.sh"
    cp "${SCRIPT_DIR}/lib/jsonc.sh"    "${MOUNT_ROOT}/root/lib/jsonc.sh"
    cp "${SCRIPT_DIR}/lib/globals.sh"  "${MOUNT_ROOT}/root/lib/globals.sh"
    mkdir -p "${MOUNT_ROOT}/root/lib/config"
    cp "${SCRIPT_DIR}/lib/config/categorized-list.sh" \
       "${MOUNT_ROOT}/root/lib/config/categorized-list.sh"
    mkdir -p "${MOUNT_ROOT}/root/lib/chroot"
    cp "${SCRIPT_DIR}/lib/chroot/extras-common.sh" \
       "${MOUNT_ROOT}/root/lib/chroot/extras-common.sh"
    find "${MOUNT_ROOT}/root/extras" -name '*.sh' -exec chmod +x {} \;
    info "Copied extras/ → /root/extras/"
  else
    warn "extras/ directory not found at ${SCRIPT_DIR}/extras" \
         "— post-install scripts won't run."
  fi

  write_fstab
  write_esp_mirror_hook "${#LAYOUT_ESP_PARTS[@]}"

  # ── Collect passwords interactively HERE, before entering the chroot ─────
  # arch-chroot redirects stdin to the heredoc, so 'read' inside the chroot
  # cannot read from the terminal. We collect all passwords now, then pass
  # them in as a JSON string so chpasswd can set them non-interactively.
  local passwords_json
  passwords_json="$(collect_passwords)"

  local root_pw
  root_pw="$(printf '%s' "$passwords_json" | jq -r '.root')"

  # ── Stage Chroot Configuration Module ───────────────────────────────────
  rm -rf "${MOUNT_ROOT}/root/lib-chroot"
  cp -r "${SCRIPT_DIR}/lib/chroot" "${MOUNT_ROOT}/root/lib-chroot"
  cp "${SCRIPT_DIR}/lib/install-state.sh" \
     "${MOUNT_ROOT}/root/lib-chroot/install-state.sh"
  cp "${SCRIPT_DIR}/lib/packages/kernel.sh" \
     "${MOUNT_ROOT}/root/lib-chroot/kernel.sh"
  cp "${SCRIPT_DIR}/lib/packages/microcode.sh" \
     "${MOUNT_ROOT}/root/lib-chroot/microcode.sh"
  cp "${SCRIPT_DIR}/lib/boot/esp-kernel-sync.sh" \
     "${MOUNT_ROOT}/root/lib-chroot/esp-kernel-sync.sh"
  cp "${SCRIPT_DIR}/lib/boot/stray-kernel.sh" \
     "${MOUNT_ROOT}/root/lib-chroot/stray-kernel.sh"
  cp "${SCRIPT_DIR}/lib/zfs/verify.sh" \
     "${MOUNT_ROOT}/root/lib-chroot/verify.sh"
  cp "${SCRIPT_DIR}/lib/impermanence-common.sh" \
     "${MOUNT_ROOT}/root/lib-chroot/impermanence-common.sh"
  cp "${SCRIPT_DIR}/lib/grub-common.sh" \
     "${MOUNT_ROOT}/root/lib-chroot/grub-common.sh"
  find "${MOUNT_ROOT}/root/lib-chroot" -name '*.sh' -exec chmod +x {} \;

  # ── Write install-state.json via the Install State module ────────────────
  install_state_write \
    "${MOUNT_ROOT}/root/lib-chroot/install-state.json" \
    "$RESOLVED_HOST_PROFILE"
  chmod 600 "${MOUNT_ROOT}/root/lib-chroot/install-state.json"

  local _host_sec_path
  _host_sec_path="$(_chroot_resolve_host_secrets)"
  ENVIRONMENT_DESKTOP="${ENVIRONMENT_DESKTOP[*]:-}" ROOT_PW="$root_pw" \
    HOST_SECRETS_FILE="$_host_sec_path" \
    arch-chroot "${MOUNT_ROOT}" bash /root/lib-chroot/configure.sh
}

# apply_impermanence
# Runs the impermanence Chroot Configuration Module from the host after
# run_profiles. Kept out of configure.sh because it moves /root into the
# persist dataset, which would erase /root/lib-chroot/ before the Profiles
# Runner can read it.
apply_impermanence() {
  [[ -d "${MOUNT_ROOT}/root/lib-chroot" ]] || return 0
  section "Applying Impermanence"
  # Tee to two logs: the target's /var/log (survives reboot, readable on
  # the booted system) and the live ISO's /tmp (readable immediately if
  # apply aborts and the system can't boot).
  local tgt_log="${MOUNT_ROOT}/var/log/install-impermanence.log"
  local iso_log="/tmp/install-impermanence.log"
  mkdir -p "$(dirname "$tgt_log")"
  arch-chroot "${MOUNT_ROOT}" bash /root/lib-chroot/impermanence.sh \
    2>&1 | tee -a "$tgt_log" "$iso_log"
}
