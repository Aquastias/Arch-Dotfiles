#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/live-keybinds.sh — keybind phase
# =============================================================================
# Part of the live Audit Run (lib/feature-audit/live.sh, ADR 0152).
#
# Used by: lib/feature-audit/live.sh (sources it).
# =============================================================================

# ── keybinds (feature-audit/11+) ─────────────────────────────────────────────

# feature_audit_push_binds_lib — stage binds-guest.sh (the guest half of the
# keybind engine) where feature_audit_guest_execute sources it.
feature_audit_push_binds_lib() {
  feature_audit_agent push "$INSTALLER_DIR/lib/feature-audit/binds-guest.sh" \
    /tmp/fa-binds >/dev/null 2>&1
}

# feature_audit_guest_execute <fn> [args…] — run a binds-guest.sh function in
# the live session.
feature_audit_guest_execute() {
  # vm-agent exec runs under set -e; the guest helpers branch on tests
  local command="set +e; source /tmp/fa-binds/binds-guest.sh;" argument
  for argument in "$@"; do command+=" $(printf '%q' "$argument")"; done
  feature_audit_agent exec "$command" 2>/dev/null
}

_live_compositor_process() {
  case "$1" in niri) echo niri ;; hyprland) echo Hyprland ;;
    umbriel) echo umbriel ;; kde) echo kwin_wayland ;; esac
}

# _live_send <chord | click:x,y> — one step of a bind's `pre`/`then` list.
_live_send() {
  case "$1" in
    click:*)
      local coordinates="${1#click:}"
      feature_audit_agent mouse move "${coordinates%,*}" \
        "${coordinates#*,}" >/dev/null 2>&1
      feature_audit_agent mouse btn left down >/dev/null 2>&1
      feature_audit_agent mouse btn left up >/dev/null 2>&1 ;;
    *) feature_audit_agent key "$1" >/dev/null 2>&1 ;;
  esac
}

# _live_bind_recover <recovery> <chord> <desktop>
_live_bind_recover() {
  case "$1" in
    escape)  feature_audit_agent key Escape >/dev/null 2>&1 ;;
    toggle)  feature_audit_agent key "$2" >/dev/null 2>&1 ;;
    key:*)   feature_audit_agent key "${1#key:}" >/dev/null 2>&1 ;;
    unlock)  feature_audit_agent unlock >/dev/null 2>&1 ;;
    session) feature_audit_agent session "$3" >/dev/null 2>&1
             feature_audit_agent idle off >/dev/null 2>&1
             feature_audit_push_binds_lib
             feature_audit_guest_execute feature_audit_binds_baseline \
               >/dev/null ;;
  esac
  sleep 1
}

# _live_mouse_chord <Mods+mouse_down|mouse_up|mouse:272|mouse:273> — hold the
# modifiers, then wheel (mouse_down/up) or drag from screen centre with the
# left (272) / right (273) button: real pointer input, like a hand would.
_live_mouse_chord() {
  local chord="$1" modifiers button
  modifiers="${chord%+mouse*}"; button="${chord##*+}"
  [[ "$modifiers" == "$chord" ]] && modifiers=""
  feature_audit_agent mouse move 16384 16384 >/dev/null 2>&1
  if [[ -n "$modifiers" ]]; then
    feature_audit_agent keydown "$modifiers" >/dev/null 2>&1 || return 1
    sleep 0.3   # the compositor must see the modifier held first
  fi
  case "$button" in
    mouse_down) feature_audit_agent mouse wheel down ;;
    mouse_up)   feature_audit_agent mouse wheel up ;;
    mouse:272|mouse:273)
      local button_side=left; [[ "$button" == mouse:273 ]] && button_side=right
      feature_audit_agent mouse move 16384 16384 && sleep 0.2 \
        && feature_audit_agent mouse btn "$button_side" down && sleep 0.2 \
        && feature_audit_agent mouse move 18000 17500 && sleep 0.2 \
        && feature_audit_agent mouse move 20000 19000 && sleep 0.2 \
        && feature_audit_agent mouse btn "$button_side" up ;;
    *) [[ -n "$modifiers" ]] \
      && feature_audit_agent keyup "$modifiers" >/dev/null 2>&1
       return 1 ;;
  esac >/dev/null 2>&1
  [[ -n "$modifiers" ]] \
    && feature_audit_agent keyup "$modifiers" >/dev/null 2>&1
  return 0
}

# _live_bind_one <plan-row-json> <desktop> — one bind as real input; prints its
# PASS/FAIL/SKIP line.
_live_bind_one() {
  local row="$1" desktop="$2" chord effect argument needs recovery settle id
  local before after rc screenshot_directory pid=""
  chord="$(jq -r .chord <<<"$row")"; effect="$(jq -r .effect <<<"$row")"
  argument="$(jq -r '.arg // ""' <<<"$row")"
  needs="$(jq -r '.needs // ""' <<<"$row")"
  recovery="$(jq -r '.recovery // ""' <<<"$row")"
  settle="$(jq -r '.settle // 1.5' <<<"$row")"
  id="bind-$(jq -r .source <<<"$row")-$chord"
  if [[ "$effect" == unverifiable ]]; then
    echo "SKIP $id unverifiable: $(jq -r '.reason // "no reason"' <<<"$row")"
    return
  fi
  screenshot_directory="Pictures/Screenshots"
  [[ "$effect" == file-created ]] && screenshot_directory="$argument"
  feature_audit_guest_execute feature_audit_binds_setup "$needs" "$effect" \
    "$argument" >/dev/null
  _live_send_steps "$row" pre send-then-wait
  before="$(feature_audit_guest_execute feature_audit_binds_state \
    "$screenshot_directory")"
  [[ "$effect" == session-ends ]] && pid="$(_live_compositor_pid "$desktop")"
  if [[ "$chord" == *mouse* ]]; then
    _live_mouse_chord "$chord" \
      || { echo "SKIP $id mouse chord not injectable"; return; }
  elif ! feature_audit_agent key "$chord" >/dev/null 2>&1; then
    echo "SKIP $id key not injectable by QEMU"
    feature_audit_guest_execute feature_audit_binds_teardown; return
  fi
  _live_send_steps "$row" "then" wait-then-send
  if [[ "$effect" == session-ends ]]; then
    _live_bind_session_end "$row" "$id" "$chord" "$desktop" "$recovery" \
      "$pid"
    return
  fi
  sleep "$settle"
  after="$(feature_audit_guest_execute feature_audit_binds_state \
    "$screenshot_directory")"
  rc=0
  feature_audit_guest_execute feature_audit_binds_evaluate "$effect" \
    "$argument" \
    "$before" "$after" >/dev/null || rc=$?
  case "$rc" in
    0) echo "PASS $id $effect" ;;
    3) echo "SKIP $id $effect not observable here (no audio device)" ;;
    *) echo "FAIL $id ($(jq -r .action <<<"$row")) expected" \
         "$effect${argument:+ $argument}, not observed" ;;
  esac
  [[ -n "$recovery" ]] && _live_bind_recover "$recovery" "$chord" "$desktop"
  feature_audit_guest_execute feature_audit_binds_teardown >/dev/null
}

# _live_send_steps <row> <pre|then> <send-then-wait|wait-then-send> — type the
# row's pre-chord or post-chord steps into the guest, a second apart.
_live_send_steps() {
  local row="$1" field="$2" order="$3" step
  while IFS= read -r step; do
    [[ -n "$step" ]] || continue
    if [[ "$order" == send-then-wait ]]; then
      _live_send "$step"; sleep 1
    else
      sleep 1; _live_send "$step"
    fi
  done < <(jq -r ".${field}[]?" <<<"$row")
}

# _live_compositor_pid <desktop> — the running compositor's PID (the oldest, so
# not a CLI client of the same name).
_live_compositor_pid() {
  feature_audit_agent sudo "pgrep -ox $(_live_compositor_process "$1")" \
    2>/dev/null
}

# _live_bind_session_end <row> <id> <chord> <desktop> <recovery> <pid> — a
# session-ends bind passes when the compositor <pid> it was sent to is gone
# within 10s (a DM relogin may already run a new one); then recover.
_live_bind_session_end() {
  local row="$1" id="$2" chord="$3" desktop="$4" recovery="$5" pid="$6"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    feature_audit_agent sudo "test -d /proc/$pid" >/dev/null 2>&1 || break
    sleep 1
  done
  if feature_audit_agent sudo "test -d /proc/$pid" >/dev/null 2>&1; then
    echo "FAIL $id ($(jq -r .action <<<"$row")) did not end the session"
  else echo "PASS $id session ended"; fi
  _live_bind_recover "${recovery:-session}" "$chord" "$desktop"
}

# feature_audit_phase_keybinds <variant-dir> <cfg> — per compositor of the set,
# every shipped bind as real keyboard input; session-ending binds last.
feature_audit_phase_keybinds() {
  local variant_directory="$1" config="$2" desktop source_name directory \
    since out row first="" why
  first="$(feature_audit_desktops "$config" | awk 'NR == 1 { print; exit }')"
  while IFS= read -r desktop; do
    [[ -n "$desktop" ]] || continue
    directory="$variant_directory/keybinds-$desktop"; mkdir -p "$directory"
    since="$(feature_audit_guest_now)"
    feature_audit_agent session "$desktop" > "$directory/agent.txt" 2>&1 || {
      echo "keybinds: session $desktop not ready" >> \
        "$directory/session-start.lines"
      continue; }
    feature_audit_agent idle off >/dev/null 2>&1 || true
    feature_audit_push_binds_lib
    feature_audit_guest_execute feature_audit_binds_baseline >/dev/null
    for source_name in $(feature_audit_binds_sources); do
      # app sources (session `*`) run once, in the first session
      case "$(feature_audit_binds_session "$source_name")" in
        "$desktop") ;;  "*") [[ "$desktop" == "$first" ]] \
          || continue ;;  *) continue ;;
      esac
      out="$directory/probe-binds-$source_name@$FA_USER.probe"
      # Probe Gate: binds this variant does not deploy are SKIPped, not judged
      if why="$(feature_audit_bind_gate "$desktop" "$config")"; then
        feature_audit_binds_plan "$source_name" | jq -r --arg w "$why" \
          'select(.effect != null) | "SKIP bind-\(.source)-\(.chord) \($w)"' \
          >> "$out"
        continue
      fi
      while IFS= read -r row; do
        _live_bind_one "$row" "$desktop" >> "$out"
      done < <(feature_audit_binds_plan "$source_name" \
        | jq -c 'select(.effect != null)' \
                 | jq -s -c 'sort_by(.session_ending // false) | .[]')
    done
    feature_audit_collect "$directory" "$since"
  done < <(feature_audit_desktops "$config")
}
