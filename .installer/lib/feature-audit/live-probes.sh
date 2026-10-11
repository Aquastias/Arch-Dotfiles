#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/live-probes.sh — probe staging + runs
# =============================================================================
# Part of the live Audit Run (lib/feature-audit/live.sh, ADR 0152).
#
# Used by: lib/feature-audit/live.sh (sources it).
# =============================================================================

# ── probes (feature-audit/09, 10) ────────────────────────────────────────────

# feature_audit_probe_directories — every program dir shipping an audit probe.
feature_audit_probe_directories() {
  local directory
  for directory in "$INSTALLER_DIR"/programs/*/*/; do
    [[ -f "$directory/audit.sh" ]] && printf '%s\n' "${directory%/}"
  done
}

# feature_audit_stage_probes <cfg> <dir…> — push probes + helper lib + the
# variant's config to the guest's /tmp/fa-probes.
feature_audit_stage_probes() {
  local config="$1" staging_directory directory name; shift
  staging_directory="$(mktemp -d)"
  mkdir -p "$staging_directory/fa-probes"
  cp "$INSTALLER_DIR/lib/feature-audit/probe-lib.sh" \
    "$staging_directory/fa-probes/_lib.sh"
  printf '%s\n' "$config" > "$staging_directory/fa-probes/config.json"
  for directory in "$@"; do
    name="${directory##*/}"
    mkdir -p "$staging_directory/fa-probes/$name"
    cp "$directory/audit.sh" "$staging_directory/fa-probes/$name/"
    [[ -f "$directory/audit-binds.jsonc" ]] \
      && cp "$directory/audit-binds.jsonc" "$staging_directory/fa-probes/$name/"
    [[ -d "$directory/audit-fixtures" ]] \
      && cp -rL "$directory/audit-fixtures" \
      "$staging_directory/fa-probes/$name/"
    # program-driven keybinds (nvim …): the matched plan rides along
    local script
    for script in $(feature_audit_binds_program_sources "$name"); do
      feature_audit_binds_plan "$script" >> \
        "$staging_directory/fa-probes/$name/binds-plan.jsonl"
      # the probe plans binds only its live dump sees with the same matcher
      cp "$INSTALLER_DIR/lib/feature-audit/binds-plan.jq" \
        "$staging_directory/fa-probes/$name/"
    done
  done
  feature_audit_agent sudo "rm -rf /tmp/fa-probes" >/dev/null 2>&1 || true
  feature_audit_agent push "$staging_directory/fa-probes" /tmp >/dev/null 2>&1
  local rc=$?
  rm -rf "$staging_directory"
  return "$rc"
}

# _live_probe_runner_script <phase> <online> <accounts…> — run every staged
# probe once per account (root + each variant user), in that user's session
# env when one is live, into /tmp/fa-probe-out.
_live_probe_runner_script() {
  printf 'PHASE=%q ONLINE=%q ACCOUNTS=%q\n' "$1" "$2" "${*:3}"
  cat <<'SH'
set -u
P=/tmp/fa-probes; O=/tmp/fa-probe-out
rm -rf "$O"; mkdir -p "$O"
sess=none
for c in niri Hyprland kwin_wayland; do
  pgrep -x "$c" >/dev/null 2>&1 && { sess="$c"; break; }
done
for d in "$P"/*/; do
  n="$(basename "$d")"; [ -f "$d/audit.sh" ] || continue
  for a in $ACCOUNTS; do
    out="$O/probe-$n@$a.probe"; err="$O/probe-$n@$a.err.lines"
    to="$(sed -n "s/^# audit-timeout: *//p" "$d/audit.sh" | head -1)"
    to="${to:-600}"
    h="$(getent passwd "$a" | cut -d: -f6)"
    common=(FA_USER="$a" FA_HOME="$h" FA_ONLINE="$ONLINE" FA_PHASE="$PHASE"
            FA_SESSION="$sess" FA_DIR="$d" FA_CONFIG="$P/config.json")
    if [ "$a" = root ]; then
      env "${common[@]}" FA_IS_ROOT=1 timeout "$to" \
        bash -c ". '$P/_lib.sh'; . '$d/audit.sh'" > "$out" 2> "$err"
    else
      uid="$(id -u "$a")"; rt="/run/user/$uid"
      wd="$(ls "$rt" 2>/dev/null | grep -E '^wayland-[0-9]+$' | head -1)"
      # compositor IPC for the probes (niri msg / hyprctl)
      ns="$(ls "$rt"/niri.*.sock 2>/dev/null | head -1)"
      his="$(ls "$rt/hypr" 2>/dev/null | head -1)"
      # X11 apps (Xwayland) need the session's DISPLAY + XAUTHORITY: read them
      # from its shell client, as a real launch would inherit them; with no
      # shell, from the user manager the compositor imported them into
      cl="$(pgrep -u "$a" -x 'plasmashell|noctalia|waybar' | head -1)"
      if [ -n "$cl" ]; then
        env_="$(tr '\0' '\n' < "/proc/$cl/environ")"
      else
        env_="$(runuser -u "$a" -- env XDG_RUNTIME_DIR="$rt" \
          systemctl --user show-environment 2>/dev/null)"
      fi
      dsp="$(sed -n 's/^DISPLAY=//p' <<<"$env_")"
      xa="$(sed -n 's/^XAUTHORITY=//p' <<<"$env_")"
      timeout "$to" runuser -u "$a" -- env -i HOME="$h" USER="$a" \
        LOGNAME="$a" SHELL="$(getent passwd "$a" | cut -d: -f7)" \
        PATH=/usr/local/bin:/usr/bin:/bin LANG=en_US.UTF-8 \
        XDG_RUNTIME_DIR="$rt" DBUS_SESSION_BUS_ADDRESS="unix:path=$rt/bus" \
        WAYLAND_DISPLAY="$wd" NIRI_SOCKET="$ns" \
        DISPLAY="$dsp" XAUTHORITY="$xa" \
        HYPRLAND_INSTANCE_SIGNATURE="$his" "${common[@]}" FA_IS_ROOT=0 \
        bash -c ". '$P/_lib.sh'; . '$d/audit.sh'" > "$out" 2> "$err"
    fi
    rc=$?
    [ "$rc" = 124 ] \
      && echo "FAIL probe-timeout $n timed out after ${to}s" >> "$out"
  done
done
chmod -R a+rX "$O"
SH
}

# feature_audit_run_probes <phase-dir> <phase> <online> <cfg> [account…] — run
# the staged probes (default accounts: root + every variant user), pull output.
feature_audit_run_probes() {
  local directory="$1" phase="$2" online="$3" config="$4"; shift 4
  local -a accounts=("$@")
  if ((${#accounts[@]} == 0)); then
    mapfile -t accounts < <(jq -r '.users[]?' <<<"$config")
    accounts=(root "${accounts[@]}")
  fi
  # a failed runner still leaves every finished probe's output: pull it
  _live_probe_runner_script "$phase" "$online" "${accounts[@]}" \
    | feature_audit_agent sudo >/dev/null 2>&1 \
    || feature_audit_fatal "$directory" "probe runner failed in the guest"
  feature_audit_pull_into /tmp/fa-probe-out "$directory" \
    || feature_audit_fatal "$directory" "could not pull probe output"
}

# feature_audit_phase_probes <variant-dir> <cfg> — every program probe offline
# (guest internet cut, SSH kept), then online: a check that only passes online
# is a runtime fetch (the feature was not fully set up at install).
feature_audit_phase_probes() {
  local variant_directory="$1" config="$2" since selected kind directory phase
  local -a directories all skips=()
  mapfile -t all < <(feature_audit_probe_directories)
  # Probe Gate: a program this variant does not select is SKIPped, not judged
  selected="$(feature_audit_selected_programs "$config")"
  while IFS=$'\t' read -r kind directory; do
    if [[ "$kind" == run ]]; then directories+=("$directory"); else \
      skips+=("$directory"); fi
  done < <(feature_audit_probe_gate_split "$selected" "${all[@]}")
  for phase in probes-offline probes-online; do
    mkdir -p "$variant_directory/$phase"
    for directory in "${skips[@]}"; do
      printf 'SKIP %s-selected not selected in this variant (Probe Gate)\n' \
        "$directory" > "$variant_directory/$phase/probe-$directory@gate.probe"
    done
  done
  ((${#directories[@]})) || return 0
  feature_audit_stage_probes "$config" "${directories[@]}" \
    || { feature_audit_fatal "$variant_directory/probes-offline" \
    "could not stage probes"; return 1; }
  since="$(feature_audit_guest_now)"
  feature_audit_agent net off >/dev/null 2>&1 \
    || feature_audit_fatal "$variant_directory/probes-offline" \
    "could not cut guest network"
  feature_audit_run_probes \
    "$variant_directory/probes-offline" probes-offline 0 "$config"
  feature_audit_agent net on >/dev/null 2>&1 \
    || feature_audit_fatal "$variant_directory/probes-offline" \
    "could not restore guest network"
  feature_audit_collect "$variant_directory/probes-offline" "$since"
  # a unit that failed with the network cut on purpose (a timer firing in
  # the window, hyprland-pure 20261006) is judged offline, not again online
  feature_audit_agent sudo "systemctl reset-failed" >/dev/null 2>&1 || true
  since="$(feature_audit_guest_now)"
  feature_audit_run_probes \
    "$variant_directory/probes-online" probes-online 1 "$config"
  feature_audit_collect "$variant_directory/probes-online" "$since"
}
