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
#   fa_bind_gate <desktop> <cfg-json>       → skip reason (rc 0) or rc 1
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

# fa_bind_gate <session-desktop> <cfg-json> — why this variant cannot judge
# binds in <session-desktop> (rc 0, reason on stdout), or rc 1 to run them.
# The bind scenes drive our curated compositor setup: a stock install ships
# none (ADR 0112), and a shell-less niri/Hyprland is the bare compositor with
# no seeded config.
fa_bind_gate() {
  local de="$1" cfg="$2"
  if [[ "$(jq -r '.environment.stock // false' <<<"$cfg")" == true ]]; then
    echo "stock install: our binds are not deployed (ADR 0112)"; return 0
  fi
  if [[ "$de" == niri || "$de" == hyprland ]] && [[ "$(jq -r \
       '.environment.wayland_shell // "noctalia"' <<<"$cfg")" == none ]]; then
    echo "no Wayland shell: bare $de, no seeded config"; return 0
  fi
  return 1
}
