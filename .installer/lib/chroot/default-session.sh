#!/usr/bin/env bash
# =============================================================================
# lib/chroot/default-session.sh — the Default Session (ADR 0159)
# =============================================================================
# The desktop a fresh login lands on is environment.desktop[0]. Each Display
# Manager Adapter seeds it as its remembered LAST session (never a forced
# default), so the operator's next pick at the greeter wins. Greeters match on
# the session's desktop entry, so this maps the desktop to that entry.
#
# Caller contract: ENVIRONMENT_DESKTOP (space-separated), ROOT (write
# prefix) set, as the Environment Runner passes them; info() defined.
#
# Used by: extras/dm/{greetd,noctalia-greeter,sddm}/*.sh, and host-side by
# lib/feature-audit/live-phases.sh (default_session_id only).
# =============================================================================

[[ -n "${_DEFAULT_SESSION_SH_SOURCED:-}" ]] && return 0
_DEFAULT_SESSION_SH_SOURCED=1

# default_session_id — the Default Session's desktop entry id (the .desktop
# basename every adapter ships or links); rc 1 when no desktop is selected.
default_session_id() {
  local desktops
  read -ra desktops <<< "${ENVIRONMENT_DESKTOP:-}"
  case "${desktops[0]:-}" in
  "")  return 1 ;;
  kde) echo plasma ;;
  *)   echo "${desktops[0]}" ;;
  esac
}

# default_session_path <dir…> — the Default Session's entry in the first <dir>
# holding it, as the greeter scanning <dir…> in order records it; rc 1 when
# none does. A curated entry is a symlink into /usr/share, so -L counts.
default_session_path() {
  local id directory entry
  id="$(default_session_id)" || return 1
  for directory in "$@"; do
    entry="${directory}/${id}.desktop"
    [[ -e "${ROOT}${entry}" || -L "${ROOT}${entry}" ]] \
      && { echo "$entry"; return 0; }
  done
  return 1
}

# default_session_write <path> <content> — write a greeter's remembered-session
# state (ROOT-prefixed), creating its directory.
default_session_write() {
  mkdir -p "${ROOT}${1%/*}"
  printf '%s' "$2" > "${ROOT}$1"
  info "Default Session seeded into $1."
}
