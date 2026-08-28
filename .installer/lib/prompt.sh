#!/usr/bin/env bash
# =============================================================================
# lib/prompt.sh — interactive credential collection primitive
# =============================================================================
# One confirmed-secret reader shared by every install-time passphrase/password
# prompt (ZFS encryption in lib/zfs/pools.sh, root password in lib/chroot.sh),
# so the "read twice, validate, retry" loop lives in one place. Each caller owns
# its own non-interactive bypass (an env preset) and surrounding warnings.
#
# Requires: lib/common.sh (warn) already sourced.
# =============================================================================

# prompt_secret <out-var> <label> [min_len] — read a secret twice from /dev/tty
# (works regardless of stdin state), looping until non-empty, >= min_len chars
# (default 1), and matching its confirmation. Writes into <out-var> via dynamic
# scope — nothing on stdout, so do NOT wrap in $(...). Prompts/warnings to stderr.
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
