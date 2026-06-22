#!/usr/bin/env bash
# =============================================================================
# lib/prompt.sh — interactive credential collection primitive
# =============================================================================
# One confirmed-secret reader shared by every install-time prompt that asks
# the operator for a passphrase or password (the ZFS encryption passphrase in
# lib/zfs/pools.sh, the root password in lib/chroot.sh). Keeps the "read twice,
# validate, retry" loop in one place so the ZFS pool module and the chroot
# module stay free of duplicated terminal I/O. Each caller owns its own
# non-interactive bypass (an env preset) and any surrounding warnings.
#
# Requires: lib/common.sh (warn) already sourced.
# =============================================================================

# prompt_secret <out-var> <label> [min_len]
# Reads a secret twice from /dev/tty (so it works regardless of stdin state),
# looping until the value is non-empty, at least <min_len> chars (default 1),
# and matches its confirmation. Writes the accepted value into the variable
# named by <out-var> via dynamic scope — nothing is echoed to stdout, so the
# call is NOT wrapped in $(...). Prompts and warnings go to stderr.
prompt_secret() {
  local __var="$1" __label="$2" __min="${3:-1}" __p1 __p2
  while true; do
    read -rsp "  ${__label}: " __p1 </dev/tty; echo >&2
    read -rsp "  Confirm ${__label}: " __p2 </dev/tty; echo >&2
    if [[ -z "$__p1" ]]; then
      warn "Cannot be empty — try again."; continue
    fi
    if (( ${#__p1} < __min )); then
      warn "Must be at least ${__min} characters."; continue
    fi
    if [[ "$__p1" != "$__p2" ]]; then
      warn "Values do not match — try again."; continue
    fi
    printf -v "$__var" '%s' "$__p1"
    return 0
  done
}
