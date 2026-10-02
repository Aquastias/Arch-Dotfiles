#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/gate.sh — program-level Probe Gate (ADR 0152)
# =============================================================================
# A probe belongs to a program; a variant that does not select the program
# (services-off, pure profiles) must not judge it. Host-side: the selected set
# is resolved like the installer does, and unselected probes become SKIPs.
#
# Public API:
#   fa_selected_programs <cfg-json>         → selected program names, sorted
#   fa_probe_gate_split <selected> <dir…>   → "run<TAB>dir" | "skip<TAB>name"
# =============================================================================

# fa_selected_programs <cfg-json> — host programs (incl. toggle-derived), every
# user's resolved programs, and the post-install Security & Backup Extras.
fa_selected_programs() {
  local cfg="$1" u
  [[ "$(type -t load_user_profile)" == function ]] || {
    # shellcheck source=../config/profile.sh
    source "$INSTALLER_DIR/lib/config/profile.sh"
  }
  [[ "$(type -t _profiles_resolve_post_install)" == function ]] || {
    # shellcheck source=../profiles/runner.sh
    source "$INSTALLER_DIR/lib/profiles/runner.sh"
  }
  {
    jq -r '.host_programs[]?' <<<"$cfg"
    for u in $(jq -r '.users[]?' <<<"$cfg"); do
      load_user_profile "$u" | jq -r '.programs[]?'
    done
    _profiles_resolve_post_install "$(jq -c '.post_install // {}' <<<"$cfg")"
  } | sort -u
}

# fa_probe_gate_split <selected> <dir…> — <selected> is newline-separated.
fa_probe_gate_split() {
  local sel=$'\n'"$1"$'\n' d n; shift
  for d in "$@"; do
    n="${d%/}"; n="${n##*/}"
    if [[ "$sel" == *$'\n'"$n"$'\n'* ]]; then printf 'run\t%s\n' "$d"
    else printf 'skip\t%s\n' "$n"; fi
  done
}
