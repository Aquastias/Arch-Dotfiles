#!/usr/bin/env bash
# =============================================================================
# lib/zfs/encryption.sh — the ZFS encryption passphrase and pool options
# =============================================================================
# Used by: lib/zfs/pools.sh (and so 03-install.sh, the layout adapters).
# Requires: lib/common.sh and lib/prompt.sh already sourced.
#
# Provides:
#   zfs_collect_encryption_passphrase — sets ZFS_PASSPHRASE before any pool
#   zfs_encryption_options            — sets ZFS_ENCRYPTION_OPTIONS from config
# =============================================================================

# -O encryption flags for zpool create; set by zfs_encryption_options,
# consumed by zfs_create_pool.
ZFS_ENCRYPTION_OPTIONS=()

# The pool passphrase; set by zfs_collect_encryption_passphrase, piped to
# zpool create by zfs_create_pool.
ZFS_PASSPHRASE=""

# Resolves the ZFS/LUKS encryption passphrase before any pool creation and
# sets the global ZFS_PASSPHRASE used by zfs_create_pool via stdin pipe.
# Precedence (ADR 0054, 0059): INSTALL_ENC_PASSPHRASE preset → guided manifest
# → unattended default → interactive /dev/tty prompt (works regardless of
# stdin state).
zfs_collect_encryption_passphrase() {
  [[ "$(install_config_encryption_enabled)" == "true" ]] || return 0
  _encryption_passphrase_without_prompt && return 0

  section "ZFS Encryption Passphrase"
  warn "Encryption is enabled. ALL data on the pools will be encrypted."
  warn "This passphrase is required at EVERY boot." \
       "Losing it means losing all data."
  echo ""

  # Shared confirmed-secret reader (lib/prompt.sh). ZFS enforces ≥8 at pool
  # creation; we pre-check here for a friendlier retry.
  prompt_secret ZFS_PASSPHRASE "ZFS passphrase" 8
  info "Passphrase set. It will be applied to all encrypted pools."
}

# _encryption_passphrase_without_prompt — sets ZFS_PASSPHRASE from the first
# non-interactive source that has one; returns 1 when the operator must type
# it.
_encryption_passphrase_without_prompt() {
  # Non-interactive seam (VM/test harness only): a preset passphrase skips the
  # /dev/tty prompt so an encrypted install runs unattended. Operator installs
  # leave INSTALL_ENC_PASSPHRASE unset and are prompted as before. ZFS itself
  # still enforces the ≥8-char rule at pool creation.
  if [[ -n "${INSTALL_ENC_PASSPHRASE:-}" ]]; then
    ZFS_PASSPHRASE="$INSTALL_ENC_PASSPHRASE"
    info "ZFS encryption passphrase taken from INSTALL_ENC_PASSPHRASE (preset)."
    return 0
  fi

  # Guided seam (ADR 0054): the Guided Installer captures the passphrase inline
  # and stages it in the no-SOPS manifest. Read it directly here — this runs
  # before /mnt is mounted, so install-state's .guided_passwords is not yet
  # written. A guided-captured passphrase skips the tty prompt.
  local manifest="${GUIDED_SECRETS_MANIFEST:-}" guided_passphrase
  if [[ -n "$manifest" && -s "$manifest" ]]; then
    guided_passphrase="$(jq -r '.enc_passphrase // ""' "$manifest" 2>/dev/null)"
    if [[ -n "$guided_passphrase" ]]; then
      ZFS_PASSPHRASE="$guided_passphrase"
      info "ZFS encryption passphrase taken from the Guided Installer."
      return 0
    fi
  fi

  # Unattended seam (ADR 0059): a non-interactive run with no preset and no
  # guided manifest — e.g. `install.sh --profile <encrypted> -y` — takes the
  # default passphrase instead of blocking on the tty prompt below. Gated on
  # INSTALL_UNATTENDED on purpose: an interactive run still prompts, so a disk
  # is never silently encrypted with a default the operator never saw. Mirrors
  # the root-password default chroot.sh already gates on the same flag.
  if [[ "${INSTALL_UNATTENDED:-0}" == "1" ]]; then
    ZFS_PASSPHRASE="$INSTALL_DEFAULT_ENC_PASSPHRASE"
    info "ZFS encryption passphrase defaulted (unattended)."
    return 0
  fi
  return 1
}

# Populates ZFS_ENCRYPTION_OPTIONS from config. The passphrase is NOT set
# here — it must be collected via zfs_collect_encryption_passphrase() before
# pool creation, then piped via stdin.
zfs_encryption_options() {
  ZFS_ENCRYPTION_OPTIONS=()
  if [[ "$(install_config_encryption_enabled)" == "true" ]]; then
    # keylocation=prompt means zpool create reads the passphrase from stdin.
    # We pipe ZFS_PASSPHRASE to it in zfs_create_pool().
    ZFS_ENCRYPTION_OPTIONS=(
      -O encryption=aes-256-gcm
      -O keyformat=passphrase
      -O keylocation=prompt
    )
  fi
}
