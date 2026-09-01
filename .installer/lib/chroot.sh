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

# Install State owns the credential-key resolution + SOPS gate. Source it if a
# standalone unit test pulled chroot.sh in without the installer's load order.
# shellcheck source=./install-state.sh
declare -F install_state_credential_path >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/install-state.sh"
# Shared confirmed-secret reader used by collect_passwords.
# shellcheck source=./prompt.sh
declare -F prompt_secret >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/prompt.sh"

# =============================================================================
# CHROOT STAGING MANIFEST
# =============================================================================
# The lib/ files the chroot phase needs, declared as data so the dependency set
# is explicit and lockstep-checkable (tests/chroot/chroot-staging.bats) instead
# of buried in cp lines. Each entry is "<src-rel-SCRIPT_DIR>|<dst-rel-stage>".
# A renamed lib then fails the bats check, not the VM. Keep in step with the
# `source` lines in lib/chroot/*.

# Staged flat into /root/lib-chroot, as siblings of the lib/chroot/* tree the
# chroot scripts source by bare name.
_CHROOT_STAGE_LIBCHROOT=(
  "lib/install-state.sh|install-state.sh"
  "lib/config/locale-parts.sh|locale-parts.sh"
  "lib/packages/kernel.sh|kernel.sh"
  "lib/packages/microcode.sh|microcode.sh"
  "lib/boot/bootloaders.sh|bootloaders.sh"
  "lib/boot/loader-entries.sh|loader-entries.sh"
  "lib/boot/esp-kernel-sync.sh|esp-kernel-sync.sh"
  "lib/boot/stray-kernel.sh|stray-kernel.sh"
  "lib/boot/zswap.sh|zswap.sh"
  "lib/zfs/verify.sh|verify.sh"
  "lib/impermanence-common.sh|impermanence-common.sh"
  "lib/grub-common.sh|grub-common.sh"
)

# Staged into /root/lib so extras/ scripts can source them (structure kept).
_CHROOT_STAGE_EXTRAS_LIB=(
  "lib/common.sh|common.sh"
  "lib/jsonc.sh|jsonc.sh"
  "lib/globals.sh|globals.sh"
  "lib/config/categorized-list.sh|config/categorized-list.sh"
  "lib/chroot/extras-common.sh|chroot/extras-common.sh"
  # hyprland.sh sources this (GPU_LIB_ONLY=1) to reuse the amd+nvidia hybrid
  # predicate for the aquamarine DRM pin (ADR 0053/0062). Must be staged here or
  # the Hyprland adapter aborts with "gpu.sh: No such file or directory".
  "lib/chroot/gpu.sh|chroot/gpu.sh"
  # niri.sh (ADR 0090) sources this pure package map so its core/preset install
  # matches exactly what the Package Resolver reports — one source of truth.
  "lib/packages/niri.sh|packages/niri.sh"
)

# _chroot_stage <dst-root> <entry...>   entry = "src-rel|dst-rel"
# Materializes manifest entries: copies each src (relative to SCRIPT_DIR) to
# dst-root/dst-rel, creating parent dirs. The single copy path for staging.
_chroot_stage() {
  local dst_root="$1"; shift
  local entry src dst
  for entry in "$@"; do
    IFS='|' read -r src dst <<< "$entry"
    mkdir -p "${dst_root}/$(dirname "$dst")"
    cp "${SCRIPT_DIR}/${src}" "${dst_root}/${dst}"
  done
}

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
  # The active Root Layout Adapter appends its filesystem-specific entries
  # (ADR 0043): ZFS → the auto-mount note; ext4/xfs/btrfs → root + swap lines
  # resolved from their post-format UUIDs. Empty for none.
  [[ -n "${LAYOUT_FSTAB_EXTRA:-}" ]] &&
    printf '\n%s\n' "$LAYOUT_FSTAB_EXTRA" >>"${MOUNT_ROOT}/etc/fstab"
  info "fstab written (${count} ESP(s))."
}

# Writes /etc/crypttab from the active Root Layout Adapter's LAYOUT_CRYPTTAB
# (ADR 0043) — the auto-opened non-root LUKS volumes (e.g. random-key swap on an
# encrypted non-ZFS root). No-op when empty (plaintext, or ZFS native crypto).
# Runs after pacstrap (so /etc exists), alongside write_fstab.
write_crypttab() {
  [[ -n "${LAYOUT_CRYPTTAB:-}" ]] || return 0
  printf '%s\n' "$LAYOUT_CRYPTTAB" >"${MOUNT_ROOT}/etc/crypttab"
  info "crypttab written."
}

# =============================================================================
# ESP MIRROR PACMAN HOOK
# =============================================================================

write_esp_mirror_hook() {
  # Install a pacman hook that rsyncs the primary ESP to all secondary ESPs
  # after any kernel or systemd-boot update (Target = usr/lib/modules/*/vmlinuz
  # and usr/lib/systemd/boot/efi/*.efi), keeping every OS disk bootable.

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

  # Install paccache cleanup hook: after every transaction, keep only the 2 most
  # recent versions per package so /var/cache/pacman/pkg doesn't grow unbounded.
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

  # section() writes to stdout; redirect to stderr so the JSON return value
  # (printed on stdout below) stays clean — same pattern as the info line above.
  section "Set root password" >&2

  # Shared confirmed-secret reader (lib/prompt.sh).
  local root_pw
  prompt_secret root_pw "Password for root"
  result="$(printf '%s' "$result" | jq --arg pw "$root_pw" '. + {root: $pw}')"
  printf '%s' "$result"
}

# The FINAL root password, resolved HERE on the host so exactly one value
# crosses into the chroot (password.sh just applies ROOT_PW). A Host Secret's
# `.root_password` overrides the interactively-collected / default value; the
# .secrets / .guided_passwords precedence (and the ADR 0025 gate) stays in the
# Install State module — the schema's owner — not re-encoded here. Resolving
# host-side also means the decrypted secret is never copied into the new root.
#   _resolve_root_password <collected-pw> <secrets-install-state.json>
_resolve_root_password() {
  local collected="$1" state="$2"
  local sec_path sec_pw
  sec_path="$(install_state_credential_path "$state" host)"
  if [[ -n "$sec_path" && -f "$sec_path" ]]; then
    sec_pw="$(jq -r '.root_password // empty' "$sec_path")"
    [[ -n "$sec_pw" ]] && { printf '%s' "$sec_pw"; return; }
  fi
  printf '%s' "$collected"
}

# Seed a valid zpool.cache into the new root's /etc/zfs so the initramfs ZFS
# hook imports every pool at boot. `zpool set` takes exactly ONE pool per call:
# passing all at once failed, and the old `cp` fallback then baked the live
# ISO's stale/empty cache into the initramfs (boot looped on "invalid or corrupt
# cache file"). Loop one pool per call. If any set fails or the file ends up
# empty, remove it so the hook falls back to scan import.
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

  # ── Seed ZFS state into the new root (ZFS only) ───────────────────────────
  # The pool cache and hostid must exist in the new system before the initramfs
  # is built, otherwise the ZFS hook cannot import the pool at boot. The archzfs
  # repo config is copied so the new system can update ZFS packages. A pure
  # non-ZFS install has no zpool / hostid / archzfs repo to seed (ADR 0043).
  if command_exists zpool; then
    local _pools=()
    mapfile -t _pools < <(zpool list -H -o name)
    _chroot_seed_zpool_cache "${MOUNT_ROOT}/etc/zfs/zpool.cache" "${_pools[@]}"
    cp /etc/hostid "${MOUNT_ROOT}/etc/hostid"
    cp /etc/pacman.conf "${MOUNT_ROOT}/etc/pacman.conf"
  fi

  # ── Copy extras/ scripts for execution inside chroot ──────────────────────
  if [[ -d "${SCRIPT_DIR}/extras" ]]; then
    # rm first so cp -r is idempotent: otherwise an existing /root/extras nests
    # the copy at /root/extras/extras/.
    rm -rf "${MOUNT_ROOT}/root/extras"
    cp -r "${SCRIPT_DIR}/extras" "${MOUNT_ROOT}/root/extras"
    # Copy lib helpers so extras scripts can source jsonc(), extras-common, etc.
    _chroot_stage "${MOUNT_ROOT}/root/lib" "${_CHROOT_STAGE_EXTRAS_LIB[@]}"
    find "${MOUNT_ROOT}/root/extras" -name '*.sh' -exec chmod +x {} \;
    # Stage the curated niri/Noctalia dotfiles (single source: the repo's
    # .config/.local) into the niri adapter so it seeds /etc/skel (ADR 0095) —
    # the extras tree is all the chroot adapter can reach. Repo-root is
    # SCRIPT_DIR/.. (SCRIPT_DIR is .installer). Harmless when niri isn't chosen.
    _niri_cur="${MOUNT_ROOT}/root/extras/desktop/niri/curated"
    if [[ -f "${SCRIPT_DIR}/../.config/niri/config.kdl" ]]; then
      install -Dm644 "${SCRIPT_DIR}/../.config/niri/config.kdl" \
        "${_niri_cur}/.config/niri/config.kdl"
      install -Dm644 "${SCRIPT_DIR}/../.config/noctalia/config.toml" \
        "${_niri_cur}/.config/noctalia/config.toml"
      install -d "${_niri_cur}/.local/bin"
      install -m755 "${SCRIPT_DIR}/../.local/bin/noctalia-"* \
        "${_niri_cur}/.local/bin/"
    fi
    info "Copied extras/ → /root/extras/"
  else
    warn "extras/ directory not found at ${SCRIPT_DIR}/extras" \
         "— post-install scripts won't run."
  fi

  write_fstab
  write_crypttab
  write_esp_mirror_hook "${#LAYOUT_ESP_PARTS[@]}"

  # ── Collect passwords interactively HERE, before entering the chroot ─────
  # arch-chroot redirects stdin to the heredoc, so 'read' inside the chroot
  # cannot read from the terminal. We collect all passwords now, then pass
  # them in as a JSON string so chpasswd can set them non-interactively.
  local passwords_json
  passwords_json="$(collect_passwords)"

  local root_pw
  root_pw="$(printf '%s' "$passwords_json" | jq -r '.root')"
  # A Host Secret's .root_password overrides the collected/default value — one
  # value, resolved host-side, crosses into the chroot (no decrypted secret is
  # copied into the new root). The secrets-bearing state is /mnt/install-state
  # .json (written by the Secrets Module / guided seam), distinct from the chroot
  # config state under /root/lib-chroot.
  root_pw="$(_resolve_root_password "$root_pw" "${MOUNT_ROOT}/install-state.json")"

  # ── Stage Chroot Configuration Module ───────────────────────────────────
  # lib/chroot/ as a tree, plus the flat siblings declared in the manifest.
  rm -rf "${MOUNT_ROOT}/root/lib-chroot"
  cp -r "${SCRIPT_DIR}/lib/chroot" "${MOUNT_ROOT}/root/lib-chroot"
  _chroot_stage "${MOUNT_ROOT}/root/lib-chroot" "${_CHROOT_STAGE_LIBCHROOT[@]}"
  find "${MOUNT_ROOT}/root/lib-chroot" -name '*.sh' -exec chmod +x {} \;

  # ── Write install-state.json via the Install State module ────────────────
  install_state_write \
    "${MOUNT_ROOT}/root/lib-chroot/install-state.json" \
    "$RESOLVED_HOST_PROFILE"
  chmod 600 "${MOUNT_ROOT}/root/lib-chroot/install-state.json"

  ENVIRONMENT_DESKTOP="${ENVIRONMENT_DESKTOP[*]:-}" \
  ENVIRONMENT_NIRI_SHELL="${ENVIRONMENT_NIRI_SHELL:-}" ROOT_PW="$root_pw" \
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
