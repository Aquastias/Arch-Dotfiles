#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/gate.sh — program-level Probe Gate (ADR 0152)
# =============================================================================
# A probe belongs to a program; a variant that does not select the program
# (services-off, pure profiles) must not judge it. Host-side: the selected set
# is resolved like the installer does, and unselected probes become SKIPs.
#
# Public API:
#   feature_audit_selected_programs <config-json>
#       → selected program names, sorted
#   feature_audit_probe_gate_split <selected> <directory…>
#       → "run<TAB>dir" | "skip<TAB>name"
#   feature_audit_bind_gate <desktop> <config-json>
#       → skip reason (rc 0) or rc 1
#
# Used by: lib/feature-audit/{check,live-probes,live-keybinds}.sh.
# =============================================================================

# shellcheck source=../config/install-config.sh
declare -F install_config_use_json >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/install-config.sh"

# feature_audit_selected_programs <cfg-json> — host programs (incl.
# toggle-derived), every user's resolved programs, and the post-install Security
# & Backup Extras.
feature_audit_selected_programs() {
  local config="$1" user
  [[ "$(type -t profile_loader_load_user)" == function ]] || {
    # shellcheck source=../config/profile-loader.sh
    source "$INSTALLER_DIR/lib/config/profile-loader.sh"
  }
  [[ "$(type -t runner_resolve_post_install)" == function ]] || {
    # shellcheck source=../profiles/runner.sh
    source "$INSTALLER_DIR/lib/profiles/runner.sh"
  }
  {
    jq -r '.host_programs[]?' <<<"$config"
    for user in $(jq -r '.users[]?' <<<"$config"); do
      profile_loader_load_user "$user" | jq -r '.programs[]?'
    done
    runner_resolve_post_install "$(jq -c '.post_install // {}' <<<"$config")" \
      "$(install_config_from_json "$config" any_zfs)"
  } | sort -u
}

# feature_audit_probe_gate_split <selected> <dir…> — <selected> is
# newline-separated.
feature_audit_probe_gate_split() {
  local selected=$'\n'"$1"$'\n' directory name; shift
  for directory in "$@"; do
    name="${directory%/}"; name="${name##*/}"
    if [[ "$selected" == *$'\n'"$name"$'\n'* ]]; then printf 'run\t%s\n' \
      "$directory"
    else printf 'skip\t%s\n' "$name"; fi
  done
}

# feature_audit_bind_gate <session-desktop> <cfg-json> — why this variant cannot
# judge binds in <session-desktop> (rc 0, reason on stdout), or rc 1 to run
# them. The bind scenes drive our curated compositor setup: a stock install
# ships none (ADR 0112), and a shell-less niri/Hyprland is the bare compositor
# with no seeded config.
feature_audit_bind_gate() {
  local desktop="$1" config="$2"
  if [[ "$(install_config_from_json "$config" stock)" == true ]]; then
    echo "stock install: our binds are not deployed (ADR 0112)"; return 0
  fi
  if [[ "$desktop" == niri || "$desktop" == hyprland ]] \
     && [[ "$(install_config_from_json "$config" wayland_shell)" == none ]]
  then
    echo "no Wayland shell: bare $desktop, no seeded config"; return 0
  fi
  return 1
}
