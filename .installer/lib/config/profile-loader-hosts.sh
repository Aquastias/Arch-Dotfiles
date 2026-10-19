#!/usr/bin/env bash
# =============================================================================
# lib/config/profile-loader-hosts.sh — Host Profile lookup by hostname
# =============================================================================
# Split from profile-loader.sh (file length), which sources it; shares its
# profile_loader_ prefix. Requires jsonc_read_optional + profile_loader_is_layer.
# =============================================================================

# profile_loader_name_for_hostname <hostname> — the Host Profile installing
# <hostname>. Profile name and hostname are decoupled (ADR 0020: `desktop`
# installs `eterniox`), so match each profile's system.hostname, a profile
# without one by its directory name (as the installer defaults it); no match
# falls back to <hostname> itself (an ad-hoc Guided config).
profile_loader_name_for_hostname() {
  local hostname="$1" profile_file name declared
  for profile_file in "${INSTALLER_DIR}"/hosts/*/profile.jsonc \
                      "${INSTALLER_DIR}"/hosts/vm/*/profile.jsonc; do
    [[ -f "$profile_file" ]] || continue
    name="${profile_file%/profile.jsonc}"; name="${name##*/}"
    profile_loader_is_layer hosts "$name" && continue
    declared="$(jsonc_read_optional "$profile_file" .system.hostname)"
    [[ "${declared:-$name}" == "$hostname" ]] \
      && { printf '%s\n' "$name"; return 0; }
  done
  printf '%s\n' "$hostname"
}
