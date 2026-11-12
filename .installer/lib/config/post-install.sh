#!/usr/bin/env bash
# =============================================================================
# lib/config/post-install.sh — Security & Backup Extras resolver (ADR 0041)
# =============================================================================
# Pure core that turns a host's `post_install.{security,backup}` object into the
# things the back-end needs: the ordered list of Program names to install, the
# all-off launch object, and shape validation. No TTY, no disk writes,
# no paru — JSON in, decision out.
#
# The post_install object shape (ADR 0041):
#   security: { firewall: "firewalld"|"ufw"|"none", antivirus, rootkit,
#               apparmor }   (firewall enum; the rest bool)
#   backup:   { zfs_auto_snapshot, borg }   (bool)
# Every sub-field is optional; an absent field is OFF (matches the old
# `bool false` accessor default).
#
# Public API:
#   post_install_default               → the all-off launch object (JSON)
#   post_install_programs   <json>     → ordered Program names, one per line
#   post_install_validate   <json>     → 0 when shape-valid, else error() + 1
#
# Used by: 03-install.sh, lib/config/{config-state,install-config,lifecycle,
# menu-owned,profile-loader}.sh, lib/packages/package-resolver.sh,
# lib/profiles/runner.sh, lib/feature-audit/manifest.sh.
# =============================================================================

# post_install_default — the selection a fresh guided run shows: every extra
# off (ADR 0157 — a blank session pre-ticks nothing; the fleet hosts declare
# their secure baseline themselves). Explicit, so the menu renders the off
# values rather than blanks; installs exactly what an absent object does.
post_install_default() {
  printf '%s%s\n' \
    '{"security":{"firewall":"none","antivirus":false,"rootkit":false,' \
    '"apparmor":false},"backup":{"zfs_auto_snapshot":false,"borg":false}}'
}

# post_install_programs <post_install_json> [any_zfs] — the ordered Program
# names the selection installs, one per line. The firewall enum picks
# firewalld / ufw / neither; the bool toggles map antivirus→clamav,
# rootkit→rkhunter, apparmor, zfs_auto_snapshot→zfs-auto-snapshot, borg.
# Canonical order (firewall first, backup last); an absent/false field
# contributes nothing. any_zfs=false (no ZFS on the install) drops
# zfs-auto-snapshot, which would otherwise pull ZFS in from the AUR; absent
# means unknown and keeps it.
post_install_programs() {
  # The selection's programs (post-install-programs.jq).
  printf '%s\n' "${1:-{\}}" | jq -r --arg zfs "${2:-true}" \
    -f "${BASH_SOURCE[0]%/*}/post-install-programs.jq"
}

# post_install_owned_programs — every Program the Security & Backup toggles can
# ever own, state-independent (the picker-filter set, mirroring
# power_owned_programs). Kept in lockstep with post_install_programs' name
# universe: firewalld / ufw, clamav, rkhunter, apparmor, zfs-auto-snapshot, borg.
# Filtered from the guided program pickers so a Security/Backup toggle is each
# program's sole menu home (ADR 0086).
post_install_owned_programs() {
  printf '%s\n' firewalld ufw clamav rkhunter apparmor zfs-auto-snapshot borg
}

# post_install_validate <post_install_json> — accept the object shape, reject
# the old bool form and malformed objects. Returns 0 when valid; otherwise
# calls error() with the offending path and returns 1. Rules: security/backup,
# when present, must be objects; security.firewall ∈ {firewalld,ufw,none};
# security.{antivirus,rootkit,apparmor} and backup.{zfs_auto_snapshot,borg},
# when present, must be bool. An absent field is valid (absent = off).
post_install_validate() {
  local bad
  # The first malformed field (post-install-validate.jq).
  bad="$(jq -rn --argjson pi "${1:-{\}}" \
    -f "${BASH_SOURCE[0]%/*}/post-install-validate.jq")" \
    || { error "post_install_validate: jq failed"; return 1; }

  if [[ -n "$bad" ]]; then
    error "Invalid post_install field: ${bad} (ADR 0041)."
    return 1
  fi
}

# post_install_guard_users <post_install_json> <user_count> — the terminal-action
# guard (M5, ADR 0041). The Security & Backup Extras install via the Primary
# User's paru pass, so a non-empty selection on a userless host can never run.
# Returns 0 when the selection is empty OR there is at least one user; otherwise
# calls error() with an actionable message and returns 1.
post_install_guard_users() {
  local pi_json="${1:-{\}}" count="${2:-0}"
  local -a programs=()
  local extras; extras="$(post_install_programs "$pi_json")" || return 1
  [[ -n "$extras" ]] && mapfile -t programs < <(printf '%s\n' "$extras")
  if ((${#programs[@]} > 0)) && (("$count" == 0)); then
    error "Security/Backup Extras install via paru and need a primary user —" \
          "add a user or clear the selections."
    return 1
  fi
}
