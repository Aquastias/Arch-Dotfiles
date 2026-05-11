#!/usr/bin/env bash
# =============================================================================
# lib/chroot.sh — System configuration inside arch-chroot
# =============================================================================
# Sourced by 03-install.sh.
# Requires: lib/common.sh already sourced.
#
# Provides:
#   write_fstab           — writes /etc/fstab from LAYOUT_ESP_PARTS (1+ ESPs)
#   write_esp_mirror_hook — installs a pacman hook that syncs secondary ESPs
#   configure_system      — seeds ZFS state, then runs the full chroot configuration
#
# configure_system stages lib/chroot/ as /root/lib-chroot/ in the new root,
# writes install-state.json (non-secret params), passes ROOT_PW via env var,
# then runs /root/lib-chroot/configure.sh (or individual sub-scripts directly
# until that orchestrator is added in a later PR).
# =============================================================================

# =============================================================================
# FSTAB WRITERS
# =============================================================================

# Pure fstab generator — no I/O. Args: one or more UUID strings (primary first).
# Returns fstab content on stdout. Test seam: call directly with fake UUIDs.
_chroot_fstab_generate() {
  (($# >= 1)) || { echo "_chroot_fstab_generate: no UUIDs provided" >&2; return 1; }
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
      echo "# EFI System Partition — secondary ${i} (kept in sync by pacman hook)"
      echo "UUID=${uuids[$i]}  /boot/efi${i}  vfat  umask=0077  0 2"
    done
  fi
  echo ""
  echo "# ZFS datasets are auto-mounted by zfs-mount-generator"
}

# Resolves UUIDs from LAYOUT_ESP_PARTS via blkid, delegates to _chroot_fstab_generate,
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
Exec = /usr/bin/bash -c 'for d in /boot/efi*/; do [[ "$d" != "/boot/efi/" ]] && rsync -a --delete /boot/efi/ "$d"; done'
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

configure_system() {
  section "Configuring System (arch-chroot)"

  # ── Seed ZFS state into the new root ──────────────────────────────────────
  # The pool cache and hostid must exist in the new system before the
  # initramfs is built, otherwise the ZFS hook cannot import the pool at boot.
  mkdir -p "${MOUNT_ROOT}/etc/zfs"
  # Copy zpool.cache into the new system so zfs-import-cache can find it.
  # Also regenerate it from the currently imported pools to ensure it's fresh.
  mkdir -p "${MOUNT_ROOT}/etc/zfs"
  local _pools=()
  mapfile -t _pools < <(zpool list -H -o name)
  zpool set cachefile="${MOUNT_ROOT}/etc/zfs/zpool.cache" "${_pools[@]}" 2>/dev/null || cp /etc/zfs/zpool.cache "${MOUNT_ROOT}/etc/zfs/" 2>/dev/null || warn "zpool.cache could not be written — zfs-import-scan will handle first boot."
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
    mkdir -p "${MOUNT_ROOT}/root/lib/chroot"
    cp "${SCRIPT_DIR}/lib/chroot/extras-common.sh" "${MOUNT_ROOT}/root/lib/chroot/extras-common.sh"
    find "${MOUNT_ROOT}/root/extras" -name '*.sh' -exec chmod +x {} \;
    info "Copied extras/ → /root/extras/"
  else
    warn "extras/ directory not found at ${SCRIPT_DIR}/extras — post-install scripts won't run."
  fi

  # ── Gather all values to pass into chroot ─────────────────────────────────
  local hostname locale timezone keymap
  local rpool swap esp_count
  local do_backup do_security

  # Hostname was already prompted (if needed) and validated in validate_install_context().
  # Use the resolved value directly — no second prompt.
  hostname="$RESOLVED_HOSTNAME"
  locale="$(cfg '.system.locale')"
  timezone="$(cfg '.system.timezone')"
  keymap="$(cfgo '.system.keymap')"
  keymap="${keymap:-us}"
  swap="$(cfgo '.options.swap')"
  swap="${swap:-true}"

  do_backup="$(cfgo '.post_install.backup')"
  do_backup="${do_backup:-false}"
  do_security="$(cfgo '.post_install.security')"
  do_security="${do_security:-false}"

  rpool="$LAYOUT_OS_POOL_NAME"
  esp_count="${#LAYOUT_ESP_PARTS[@]}"
  write_fstab
  write_esp_mirror_hook "$esp_count"

  # ── Run configuration inside chroot ───────────────────────────────────────
  # Values are passed as positional args ($1–$13) to avoid export issues.
  # The heredoc is quoted ('CHROOT') so variable expansion happens INSIDE
  # the chroot shell, not in the outer script.

  # Kernel and bootloader selection from config
  local kernel
  kernel="$(cfgo '.options.kernel')"
  kernel="${kernel:-lts}"
  local bootloader
  bootloader="$(cfgo '.options.bootloader')"
  bootloader="${bootloader:-systemd-boot}"

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
  find "${MOUNT_ROOT}/root/lib-chroot" -name '*.sh' -exec chmod +x {} \;

  # ── Write install-state.json (non-secret install params for chroot scripts)
  jq -n \
    --arg hostname    "$hostname"   \
    --arg timezone    "$timezone"   \
    --arg locale      "$locale"     \
    --arg keymap      "$keymap"     \
    --arg kernel      "$kernel"     \
    --arg bootloader  "$bootloader" \
    --arg rpool       "$rpool"      \
    --arg swap        "$swap"       \
    --argjson esp_count "$esp_count" \
    --argjson extras_backup   "$([[ "$do_backup"   == "true" ]] && printf 'true' || printf 'false')" \
    --argjson extras_security "$([[ "$do_security" == "true" ]] && printf 'true' || printf 'false')" \
    '{ hostname:$hostname, timezone:$timezone, locale:$locale, keymap:$keymap,
       kernel:$kernel, bootloader:$bootloader, rpool:$rpool, swap:$swap,
       esp_count:$esp_count,
       extras:{ backup:$extras_backup, security:$extras_security } }' \
    > "${MOUNT_ROOT}/root/lib-chroot/install-state.json"
  chmod 600 "${MOUNT_ROOT}/root/lib-chroot/install-state.json"

  ENVIRONMENT_DESKTOP="${ENVIRONMENT_DESKTOP[*]:-}" ROOT_PW="$root_pw" arch-chroot "${MOUNT_ROOT}" bash /root/lib-chroot/configure.sh
}
