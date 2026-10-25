#!/usr/bin/env bash
# =============================================================================
# lib/chroot.sh — System configuration inside arch-chroot
# =============================================================================
# Sourced by 03-install.sh.
# Requires: lib/common.sh and lib/install-state.sh already sourced.
#
# Provides:
#   chroot_write_fstab           — writes /etc/fstab from LAYOUT_ESP_PARTS
#                                  (1+ ESPs)
#   chroot_write_esp_mirror_hook — installs a pacman hook that syncs
#                                  secondary ESPs
#   chroot_configure_system — seeds ZFS state, then runs the full chroot
#                      configuration
#
# chroot_configure_system stages lib/chroot/ as /root/lib-chroot/ in the new
# root, delegates install-state.json writing to install_state_write, passes
# ROOT_PW via env var, then runs /root/lib-chroot/configure.sh.
# =============================================================================

# Install State owns the credential-key resolution + SOPS gate. Source it if a
# standalone unit test pulled chroot.sh in without the installer's load order.
# shellcheck source=./install-state.sh
declare -F install_state_credential_path >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/install-state.sh"
# Shared confirmed-secret reader used by chroot_collect_passwords.
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
  "lib/boot/bootloader.sh|bootloader.sh"
  "lib/boot/loader-entries.sh|loader-entries.sh"
  "lib/boot/esp-kernel-sync.sh|esp-kernel-sync.sh"
  "lib/boot/stray-kernel.sh|stray-kernel.sh"
  "lib/boot/lts-hold.sh|lts-hold.sh"
  "lib/boot/zswap.sh|zswap.sh"
  "lib/boot/lsm.sh|lsm.sh"
  "lib/boot/vm-video.sh|vm-video.sh"
  "lib/boot/esp-stage.sh|esp-stage.sh"
  "lib/zfs/verify.sh|verify.sh"
  "lib/packages/archzfs-kernel.sh|archzfs-kernel.sh"
  "lib/packages/archive.sh|archive.sh"
  "lib/impermanence-common.sh|impermanence-common.sh"
)

# Staged into /root/lib so extras/ scripts can source them (structure kept).
_CHROOT_STAGE_EXTRAS_LIB=(
  "lib/common.sh|common.sh"
  "lib/jsonc.sh|jsonc.sh"
  "lib/globals.sh|globals.sh"
  # common.sh sources the layout accessors (ticket 06 moved them there).
  "lib/layout/state.sh|layout/state.sh"
  "lib/config/categorized-list.sh|config/categorized-list.sh"
  "lib/chroot/extras-common.sh|chroot/extras-common.sh"
  # hyprland.sh sources this (GPU_LIB_ONLY=1) to reuse the amd+nvidia hybrid
  # predicate for the aquamarine DRM pin (ADR 0053/0062). Must be staged here or
  # the Hyprland adapter aborts with "gpu.sh: No such file or directory".
  "lib/chroot/gpu.sh|chroot/gpu.sh"
  # niri.sh (ADR 0090) sources this pure package map so its core/preset install
  # matches exactly what the Package Resolver reports — one source of truth.
  "lib/packages/niri.sh|packages/niri.sh"
  # umbriel.sh (ADR 0159) sources its pure repo package map the same way.
  "lib/packages/umbriel.sh|packages/umbriel.sh"
  # noctalia-preset.sh sources this pure Noctalia preset + plugin map.
  "lib/packages/noctalia.sh|packages/noctalia.sh"
  # The shared Noctalia work-shell preset (ADR 0097), sourced by BOTH the niri
  # and Hyprland adapters — the one place the preset logic lives.
  "lib/chroot/noctalia-preset.sh|chroot/noctalia-preset.sh"
  "lib/chroot/noctalia-skeleton.sh|chroot/noctalia-skeleton.sh"
  # noctalia-preset.sh guard-sources this for its path helpers.
  "lib/chroot/chroot-common.sh|chroot/chroot-common.sh"
  # Both greetd Display Manager Adapters source this shared base (ADR 0158).
  "lib/chroot/greetd-config.sh|chroot/greetd-config.sh"
  # Every Display Manager Adapter seeds the Default Session (ADR 0159).
  "lib/chroot/default-session.sh|chroot/default-session.sh"
)

# _chroot_stage <dst-root> <entry...>   entry = "src-rel|dst-rel"
# Materializes manifest entries: copies each src (relative to SCRIPT_DIR) to
# dst-root/dst-rel, creating parent dirs. The single copy path for staging.
_chroot_stage() {
  local destination_root="$1"; shift
  local entry source_path destination
  for entry in "$@"; do
    IFS='|' read -r source_path destination <<< "$entry"
    mkdir -p "${destination_root}/$(parent_directory "$destination")"
    cp "${SCRIPT_DIR}/${source_path}" "${destination_root}/${destination}"
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
chroot_write_fstab() {
  local count="${#LAYOUT_ESP_PARTS[@]}"
  ((count >= 1)) || error "chroot_write_fstab: LAYOUT_ESP_PARTS is empty."
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
# Runs after pacstrap (so /etc exists), alongside chroot_write_fstab.
chroot_write_crypttab() {
  [[ -n "${LAYOUT_CRYPTTAB:-}" ]] || return 0
  printf '%s\n' "$LAYOUT_CRYPTTAB" >"${MOUNT_ROOT}/etc/crypttab"
  info "crypttab written."
}

# =============================================================================
# ESP MIRROR PACMAN HOOK
# =============================================================================

chroot_write_esp_mirror_hook() {
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
}

# chroot_write_paccache_hook — after every transaction, keep only the 2 most
# recent versions per package so /var/cache/pacman/pkg doesn't grow unbounded.
# Every install gets it (it once sat behind the mirror hook's multi-ESP gate).
chroot_write_paccache_hook() {
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
Exec = /usr/bin/paccache -rk2
HOOK
  info "paccache auto-cleanup hook installed."
}

# =============================================================================
# CHROOT CONFIGURATION
# =============================================================================

chroot_collect_passwords() {
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
  local root_password
  prompt_secret root_password "Password for root"
  result="$(printf '%s' "$result" \
    | jq --arg pw "$root_password" '. + {root: $pw}')"
  printf '%s' "$result"
}

# The FINAL root password, resolved HERE on the host so exactly one value
# crosses into the chroot (password.sh just applies ROOT_PW). A Host Secret's
# `.root_password` overrides the interactively-collected / default value; the
# .secrets / .guided_passwords precedence (and the ADR 0025 gate) stays in the
# Install State module — the schema's owner — not re-encoded here. Resolving
# host-side also means the decrypted secret is never copied into the new root.
#   _chroot_resolve_root_password <collected-pw> <secrets-install-state.json>
_chroot_resolve_root_password() {
  local collected="$1" state="$2"
  local secret_path secret_password
  secret_path="$(install_state_credential_path "$state" host)"
  if [[ -n "$secret_path" && -f "$secret_path" ]]; then
    secret_password="$(jq -r '.root_password // empty' "$secret_path")"
    [[ -n "$secret_password" ]] && { printf '%s' "$secret_password"; return; }
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
  local pool
  mkdir -p "$(parent_directory "$cache")"
  for pool in "$@"; do
    if ! zpool set cachefile="$cache" "$pool" 2>/dev/null; then
      rm -f "$cache"
      warn "zpool.cache could not be written for '$pool' —" \
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

chroot_configure_system() {
  section "Configuring System (arch-chroot)"

  # pacstrap read the HOST pacman.conf (Optional Repositories, ADR 0072;
  # Pacman Options, ADR 0074; archzfs on ZFS); the target inherits it on
  # every layout, or a non-ZFS install loses e.g. [multilib].
  cp /etc/pacman.conf "${MOUNT_ROOT}/etc/pacman.conf"
  # Keep only the installed version in the cache going forward. Set here, after
  # the copy: written earlier (pacstrap step) the copy overwrote it.
  grep -q '^CleanMethod' "${MOUNT_ROOT}/etc/pacman.conf" \
    || sed -i 's/^#CleanMethod.*/CleanMethod = KeepCurrent/' \
      "${MOUNT_ROOT}/etc/pacman.conf"

  _chroot_seed_zfs_state
  _chroot_copy_extras

  chroot_write_fstab
  chroot_write_crypttab
  chroot_write_esp_mirror_hook "${#LAYOUT_ESP_PARTS[@]}"
  chroot_write_paccache_hook

  # ── Collect passwords interactively HERE, before entering the chroot ─────
  # arch-chroot redirects stdin to the heredoc, so 'read' inside the chroot
  # cannot read from the terminal. We collect all passwords now, then pass
  # them in as a JSON string so chpasswd can set them non-interactively.
  local passwords_json root_password
  passwords_json="$(chroot_collect_passwords)"
  root_password="$(printf '%s' "$passwords_json" | jq -r '.root')"
  # A Host Secret's .root_password overrides the collected/default value — one
  # value, resolved host-side, crosses into the chroot (no decrypted secret is
  # copied into the new root). The secrets-bearing state is /mnt/install-state
  # .json (written by the Secrets Module / guided seam), distinct from the chroot
  # config state under /root/lib-chroot.
  root_password="$(_chroot_resolve_root_password "$root_password" \
    "${MOUNT_ROOT}/install-state.json")"

  _chroot_stage_configuration_module

  ENVIRONMENT_DESKTOP="${ENVIRONMENT_DESKTOP[*]:-}" \
  ENVIRONMENT_WAYLAND_SHELL="${ENVIRONMENT_WAYLAND_SHELL:-}" \
  ENVIRONMENT_STOCK="${ENVIRONMENT_STOCK:-}" \
  ROOT_PW="$root_password" \
    arch-chroot "${MOUNT_ROOT}" bash /root/lib-chroot/configure.sh
}

# The pool cache and hostid must exist in the new system before the initramfs
# is built, otherwise the ZFS hook cannot import the pool at boot. A pure
# non-ZFS install has no zpool / hostid to seed (ADR 0043).
_chroot_seed_zfs_state() {
  command_exists zpool || return 0
  local pools=()
  mapfile -t pools < <(zpool list -H -o name)
  _chroot_seed_zpool_cache "${MOUNT_ROOT}/etc/zfs/zpool.cache" "${pools[@]}"
  cp /etc/hostid "${MOUNT_ROOT}/etc/hostid"
}

# Copy extras/ scripts (and the lib helpers they source) for execution inside
# the chroot, plus the curated compositor payloads the DE adapters seed.
_chroot_copy_extras() {
  if [[ ! -d "${SCRIPT_DIR}/extras" ]]; then
    warn "extras/ directory not found at ${SCRIPT_DIR}/extras" \
         "— post-install scripts won't run."
    return 0
  fi
  # rm first so cp -r is idempotent: otherwise an existing /root/extras nests
  # the copy at /root/extras/extras/.
  rm -rf "${MOUNT_ROOT}/root/extras"
  cp -r "${SCRIPT_DIR}/extras" "${MOUNT_ROOT}/root/extras"
  # Copy lib helpers so extras scripts can source jsonc(), extras-common, etc.
  _chroot_stage "${MOUNT_ROOT}/root/lib" "${_CHROOT_STAGE_EXTRAS_LIB[@]}"
  find "${MOUNT_ROOT}/root/extras" -name '*.sh' -exec chmod +x {} \;
  # Stage the curated niri/Noctalia dotfiles (single source: the repo's
  # .config/.local) into the niri adapter so it seeds /etc/skel (ADR 0095) —
  # the extras tree is all the chroot adapter can reach. Same single-source
  # staging for Hyprland (ADR 0097): it seeds the SAME Noctalia payload, so a
  # Hyprland+Noctalia box gets a config.toml byte-identical to the niri one.
  # Harmless when a compositor isn't chosen.
  _chroot_stage_curated_compositor niri niri/config.kdl
  _chroot_stage_curated_compositor hyprland hypr/hyprland.lua
  info "Copied extras/ → /root/extras/"
}

# _chroot_stage_curated_compositor <adapter> <entry config> — stage the
# compositor's entry config + its conf.d/ part files (split config, ADR 0107),
# then the shared Noctalia payload, into the adapter's curated dir. Skipped
# when the repo has no such entry config. Repo-root is SCRIPT_DIR/..
# (SCRIPT_DIR is .installer).
_chroot_stage_curated_compositor() {
  local adapter="$1" entry="$2"
  local repo="${SCRIPT_DIR}/.."
  local curated="${MOUNT_ROOT}/root/extras/desktop/${adapter}/curated"
  [[ -f "${repo}/.config/${entry}" ]] || return 0
  install -Dm644 "${repo}/.config/${entry}" "${curated}/.config/${entry}"
  local dropin_directory="${entry%/*}/conf.d"
  install -d "${curated}/.config/${dropin_directory}"
  install -m644 "${repo}/.config/${dropin_directory}/"* \
    "${curated}/.config/${dropin_directory}/"
  _chroot_stage_noctalia_payload "$curated"
}

# The Noctalia payload both compositor adapters seed from their curated dir.
_chroot_stage_noctalia_payload() {
  local curated="$1" repo="${SCRIPT_DIR}/.."
  install -Dm644 "${repo}/.config/noctalia/config.toml" \
    "${curated}/.config/noctalia/config.toml"
  # User-template inputs (ADR 0128/0129): config.toml declares
  # [theme.templates.user.*] whose input_path lives here; stage the dir so
  # the preset seeds it — live palette-follow on seed-only boxes (pi + zsh),
  # not just stow'd ones.
  install -d "${curated}/.config/noctalia/templates"
  install -m644 "${repo}/.config/noctalia/templates/"* \
    "${curated}/.config/noctalia/templates/"
  install -d "${curated}/.local/bin"
  install -m755 "${repo}/.local/bin/noctalia-"* "${curated}/.local/bin/"
  # pcmanfm-qt settings + its right-click actions (ADR 0100): the preset
  # seeds these from the curated dir, so they must be staged too.
  install -Dm644 "${repo}/.config/pcmanfm-qt/lxqt/settings.conf" \
    "${curated}/.config/pcmanfm-qt/lxqt/settings.conf"
  install -d "${curated}/.local/share/file-manager/actions"
  install -m644 "${repo}/.local/share/file-manager/actions/"*.desktop \
    "${curated}/.local/share/file-manager/actions/"
  # qt6ct.conf — the App Theming Bridge's Qt half (ADR 0102/0108): the preset
  # seeds it from the curated dir, so it must be staged too (it was stow-only,
  # so it never reached a fresh box — the white-Qt-apps bug, ADR 0108).
  install -Dm644 "${repo}/.config/qt6ct/qt6ct.conf" \
    "${curated}/.config/qt6ct/qt6ct.conf"
}

# Stage the Chroot Configuration Module — lib/chroot/ as a tree, plus the flat
# siblings declared in the manifest — and write its install-state.json.
_chroot_stage_configuration_module() {
  rm -rf "${MOUNT_ROOT}/root/lib-chroot"
  cp -r "${SCRIPT_DIR}/lib/chroot" "${MOUNT_ROOT}/root/lib-chroot"
  _chroot_stage "${MOUNT_ROOT}/root/lib-chroot" "${_CHROOT_STAGE_LIBCHROOT[@]}"
  find "${MOUNT_ROOT}/root/lib-chroot" -name '*.sh' -exec chmod +x {} \;

  install_state_write "${MOUNT_ROOT}/root/lib-chroot/install-state.json"
  chmod 600 "${MOUNT_ROOT}/root/lib-chroot/install-state.json"
}

# chroot_apply_impermanence
# Runs the impermanence Chroot Configuration Module from the host after
# runner_run_profiles. Kept out of configure.sh because it moves /root into the
# persist dataset, which would erase /root/lib-chroot/ before the Profiles
# Runner can read it.
chroot_apply_impermanence() {
  [[ -d "${MOUNT_ROOT}/root/lib-chroot" ]] || return 0
  section "Applying Impermanence"
  # Tee to two logs: the target's /var/log (survives reboot, readable on
  # the booted system) and the live ISO's /tmp (readable immediately if
  # apply aborts and the system can't boot).
  local target_log="${MOUNT_ROOT}/var/log/install-impermanence.log"
  local iso_log="/tmp/install-impermanence.log"
  mkdir -p "$(parent_directory "$target_log")"
  arch-chroot "${MOUNT_ROOT}" bash /root/lib-chroot/impermanence.sh \
    2>&1 | tee -a "$target_log" "$iso_log"
}
