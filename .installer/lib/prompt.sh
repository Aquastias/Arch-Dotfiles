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

# prompt_secret <label> [min_len] — read a secret twice from /dev/tty (works
# regardless of stdin state), looping until non-empty, >= min_len chars
# (default 1), and matching its confirmation. Prints the secret on stdout —
# call it as  secret="$(prompt_secret "Label")". Prompts/warnings to stderr.
prompt_secret() {
  local label="$1" minimum_length="${2:-1}"
  local first_entry confirmation
  while true; do
    read -rsp "  ${label}: " first_entry </dev/tty; echo >&2
    read -rsp "  Confirm ${label}: " confirmation </dev/tty; echo >&2
    if [[ -z "$first_entry" ]]; then
      warn "Cannot be empty — try again." >&2; continue
    fi
    if (( ${#first_entry} < minimum_length )); then
      warn "Must be at least ${minimum_length} characters." >&2; continue
    fi
    if [[ "$first_entry" != "$confirmation" ]]; then
      warn "Values do not match — try again." >&2; continue
    fi
    printf '%s' "$first_entry"
    return 0
  done
}
