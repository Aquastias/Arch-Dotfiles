#!/usr/bin/env bash
# =============================================================================
# lib/sentinel-watcher.sh — Installer-completion sentinel reader
# =============================================================================
# Public:
#   sentinel_watcher_wait LOG_PATH TIMEOUT_SEC
#       Watch LOG_PATH for the first line matching the exact form
#       `===INSTALLER-EXIT-N===` (where N is a non-negative integer; trailing
#       whitespace tolerated). Returns N as the function's exit status.
#       Returns 124 if TIMEOUT_SEC seconds elapse with no match.
#
#       The log file may not exist when called; the function tolerates a
#       file that appears mid-window. The log is never modified or deleted.
#
#       No libvirt or network dependency — pure file watcher.
#
# The sentinel format is a hard contract with .os/lib/seed-generator.sh
# (which writes it via the test VM's runcmd). Do not change this regex
# without updating the writer in lockstep.
#
# Implementation: a polling loop rather than `tail -F`, because the file may
# not yet exist when the call starts and the polling form is simpler and has
# no orphan-process risk on early returns.
# =============================================================================

# Match `===INSTALLER-EXIT-<digits>===` at start of line, tolerating
# trailing whitespace. Anchored to start so the line cannot embed the marker
# inside other text.
SENTINEL_WATCHER_REGEX='^===INSTALLER-EXIT-([0-9]+)===[[:space:]]*$'

sentinel_watcher_wait() {
  local log_path="$1" timeout_sec="$2"

  [[ -n "$log_path" ]] || {
    echo "sentinel-watcher: log path is empty" >&2
    return 2
  }
  [[ "$timeout_sec" =~ ^[0-9]+$ ]] || {
    echo "sentinel-watcher: timeout must be a non-negative integer" >&2
    return 2
  }

  local deadline=$((SECONDS + timeout_sec))
  local line code

  while ((SECONDS < deadline)); do
    if [[ -f "$log_path" ]]; then
      # Find the first matching line. grep -m1 stops scanning on first hit;
      # combined with the regex anchor it's a strict O(n) scan.
      line="$(grep -E -m1 "$SENTINEL_WATCHER_REGEX" "$log_path" \
        2>/dev/null || true)"
      if [[ "$line" =~ $SENTINEL_WATCHER_REGEX ]]; then
        code="${BASH_REMATCH[1]}"
        # Defensive: if the value somehow exceeds the bash exit-status range,
        # bash will modulo the rest. The test contract only asserts [0,255].
        return "$code"
      fi
    fi
    sleep 0.1
  done

  return 124
}
