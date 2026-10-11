#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/binds-guest.sh — guest-side keybind state + effects
# =============================================================================
# Staged into the guest and sourced inside the live session (VM Agent Control
# `exec`). The host sends each bind as real input between a
# `feature_audit_binds_state` before/after pair, then
# `feature_audit_binds_evaluate` judges the declared effect from the two
# snapshots (ADR 0152). Compositor-aware: niri (`niri msg`), Hyprland
# (`hyprctl`), KDE (KWin D-Bus + spectacle).
#
# Effects: window-opens <app-re> | window-closes | workspace <n> |
#   workspace-changes | focus-changes | layout-changes | window-changes
#   (focus or layout) | screen-changes | file-created <dir> | audio-changes |
#   session-ends
#
# Used by: pushed into the guest session by lib/feature-audit/live-keybinds.sh
# (feature_audit_push_binds_lib); run via feature_audit_guest_execute.
# =============================================================================

FA_BIND_CLASS=fa-bind

_binds_guest_compositor() {
  local compositor
  for compositor in niri Hyprland kwin_wayland; do
    pgrep -x "$compositor" >/dev/null 2>&1 && { echo "$compositor"; return; }
  done
  echo none
}

# _binds_guest_windows — normalized window list JSON: [{id, app, ws, focused,
# geo}].
_binds_guest_windows() {
  case "$(_binds_guest_compositor)" in
    niri) niri msg -j windows 2>/dev/null | jq -c 'map({id, app: .app_id,
            ws: .workspace_id, focused: .is_focused,
            geo: {f: .is_floating, l: .layout}})' ;;
    Hyprland) hyprctl -j clients 2>/dev/null | jq -c --arg a \
            "$(hyprctl -j activewindow 2>/dev/null | jq -r '.address // ""')" \
            'map({id: .address, app: .class, ws: .workspace.id,
                  focused: (.address == $a),
                  geo: {at, size, floating, fullscreen}})' ;;
    kwin_wayland) _binds_guest_kwin_windows ;;
    *) echo '[]' ;;
  esac
}

# _binds_guest_kwin_windows — KWin has no JSON IPC; a one-shot KWin script
# prints the window list to the journal, read back by a marker.
_binds_guest_kwin_windows() {
  local marker="fa-kwin-$$-$RANDOM" script
  script="$(mktemp --suffix=.js)"
  cat > "$script" <<JS
var out = [];
workspace.windowList().forEach(function (w) {
  if (!w.normalWindow) return;
  out.push({id: w.internalId.toString(), app: w.resourceClass,
            ws: w.desktops.length ? w.desktops[0].x11DesktopNumber : 0,
            focused: w === workspace.activeWindow,
            geo: {x: w.frameGeometry.x, y: w.frameGeometry.y,
                  w: w.frameGeometry.width, h: w.frameGeometry.height,
                  full: w.fullScreen, max: w.maximizeMode,
                  min: w.minimized}});
});
print("$marker" + JSON.stringify(out));
JS
  local id
  id="$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript \
    "$script" "$marker" 2>/dev/null)"
  qdbus6 org.kde.KWin "/Scripting/Script${id}" \
    org.kde.kwin.Script.run >/dev/null 2>&1
  sleep 0.5
  qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$marker" \
    >/dev/null 2>&1
  rm -f "$script"
  journalctl --user -q -o cat --since "-10s" 2>/dev/null \
    | MARKER="$marker" awk '
        index($0, ENVIRON["MARKER"]) {
          last = substr($0, index($0, ENVIRON["MARKER"]) \
            + length(ENVIRON["MARKER"]))
        }
        END { print (last == "" ? "[]" : last) }'
}

# _binds_guest_workspace — {idx, id, count} of the focused output's active
# workspace.
_binds_guest_workspace() {
  case "$(_binds_guest_compositor)" in
    niri) niri msg -j workspaces 2>/dev/null | jq -c '
            (map(select(.is_focused))[0]) as $f
            | {idx: $f.idx, id: $f.id,
               count: (map(select(.output == $f.output)) | length)}' ;;
    # Hyprland creates a numbered workspace on demand: no clamp
    Hyprland) hyprctl -j activeworkspace 2>/dev/null \
            | jq -c '{idx: .id, id: .id, count: 99}' ;;
    kwin_wayland)
      local compositor number
      compositor="$(qdbus6 org.kde.KWin /KWin org.kde.KWin.currentDesktop \
        2>/dev/null)"
      number="$(qdbus6 org.kde.KWin /VirtualDesktopManager \
        org.freedesktop.DBus.Properties.Get org.kde.KWin.VirtualDesktopManager \
        count 2>/dev/null)"
      jq -cn --argjson c "${compositor:-0}" --argjson n "${number:-0}" \
        '{idx: $c, id: $c, count: $n}' ;;
    *) echo '{}' ;;
  esac
}

_binds_guest_shot_hash() {
  local shot_file; shot_file="$(mktemp --suffix=.png)"
  case "$(_binds_guest_compositor)" in
    kwin_wayland) timeout 15 spectacle -bnf -o "$shot_file" >/dev/null 2>&1 ;;
    *) timeout 10 grim "$shot_file" >/dev/null 2>&1 ;;
  esac
  sha1sum "$shot_file" 2>/dev/null | awk '{ print substr($0, 1, 12) }'
  rm -f "$shot_file"
}

_binds_guest_audio() {
  { wpctl get-volume @DEFAULT_AUDIO_SINK@
    wpctl get-volume @DEFAULT_AUDIO_SOURCE@; } \
    2>/dev/null | awk '{ printf "%s ", $0 }'
}

# feature_audit_binds_state [home-rel-dir] — snapshot JSON of everything an
# effect can observe (the dir is where file-created counts new files).
feature_audit_binds_state() {
  local directory="$HOME/${1:-Pictures/Screenshots}"
  jq -cn --arg comp "$(_binds_guest_compositor)" --argjson w \
    "$(_binds_guest_windows)" \
    --argjson ws "$(_binds_guest_workspace)" --arg shot \
    "$(_binds_guest_shot_hash)" \
    --arg audio "$(_binds_guest_audio)" \
    --arg files "$(find "$directory" -type f 2>/dev/null | grep -c .)" '
    { comp: $comp, windows: $w, ws: $ws, shot: $shot, audio: $audio,
      files: ($files | tonumber),
      focused: ([$w[] | select(.focused)][0].id // null),
      layout: ($w | map({id, ws, geo}) | tostring) }'
}

# feature_audit_binds_setup <needs> <effect> <arg> — reset to a known scene
# before a bind: test windows on the first workspace (+ a stack / floating / 2nd
# workspace when the bind needs one). Best-effort; the effect check is the
# judge. _binds_guest_hyprland <lua> — a Hyprland dispatch. The shipped config
# is Lua, where `hyprctl dispatch` evaluates Lua: legacy dispatcher names fail.
_binds_guest_hyprland() { hyprctl dispatch "$1" >/dev/null 2>&1; }

feature_audit_binds_setup() {
  local needs="$1" effect="$2" argument="${3:-}" compositor want=2 direction=""
  compositor="$(_binds_guest_compositor)"
  [[ "$needs" =~ windows:([0-9]+) ]] && want="${BASH_REMATCH[1]}"
  [[ "$needs" =~ dir:([a-z]+) ]] && direction="${BASH_REMATCH[1]}"
  # Hyprland's dwindle needs a third window for a vertical neighbour
  [[ -n "$direction" && "$compositor" == Hyprland && "$want" -lt 3 ]] \
    && want=3
  _binds_guest_go_to_workspace "$compositor" 1
  _binds_guest_open_test_windows "$want"
  _binds_guest_arrange "$compositor" "$needs"
  _binds_guest_apply_need_tokens "$compositor" "$needs"
  [[ -n "$direction" ]] \
    && _binds_guest_focus_for_directory "$compositor" "$direction"
  # a workspace-N bind must start somewhere else to prove it moved (niri
  # clamps N to the last workspace, so only `1` needs to start further down)
  if [[ "$effect" == workspace && "$argument" == 1 ]]; then
    case "$compositor" in
      niri) _binds_guest_niri focus-workspace-down ;;
      Hyprland) _binds_guest_hyprland "hl.dsp.focus({ workspace = 10 })" ;;
      kwin_wayland) qdbus6 org.kde.KWin /KWin \
        org.kde.KWin.setCurrentDesktop 2 >/dev/null 2>&1 ;;
    esac
  fi
  sleep 0.5
}

# _binds_guest_niri <action…> — a niri `msg action`.
_binds_guest_niri() { niri msg action "$@" >/dev/null 2>&1; }

# _binds_guest_go_to_workspace <compositor> <n> — focus workspace / desktop n.
_binds_guest_go_to_workspace() {
  case "$1" in
    niri) _binds_guest_niri focus-workspace "$2" ;;
    Hyprland) _binds_guest_hyprland "hl.dsp.focus({ workspace = $2 })" ;;
    kwin_wayland) qdbus6 org.kde.KWin /KWin \
      org.kde.KWin.setCurrentDesktop "$2" >/dev/null 2>&1 ;;
  esac
}

# _binds_guest_open_test_windows <want> — open test kitty windows until the
# first (current) workspace holds <want> of them.
_binds_guest_open_test_windows() {
  local want="$1" count
  count="$(_binds_guest_windows | jq --arg c "$FA_BIND_CLASS" \
    --argjson w "$(_binds_guest_workspace | jq .id)" \
    '[.[] | select(.app == $c and .ws == $w)] | length')"
  while ((count < want)); do
    setsid -f kitty --class "$FA_BIND_CLASS" >/dev/null 2>&1
    sleep 1.5; count=$((count + 1))
  done
}

# _binds_guest_arrange <compositor> <needs> — the window layout a bind needs:
# stacked, floating, a test window on workspace 2, or starting on workspace 2.
_binds_guest_arrange() {
  local compositor="$1" needs="$2"
  [[ "$needs" == *stack* && "$compositor" == niri ]] \
    && _binds_guest_niri consume-or-expel-window-left \
      # focused joins the left column
  if [[ "$needs" == *floating* ]]; then
    case "$compositor" in
      niri) _binds_guest_niri toggle-window-floating ;;
      Hyprland) _binds_guest_hyprland \
        'hl.dsp.window.float({ action = "toggle" })' ;;
    esac
  fi
  # ws2win: one test window on workspace 2, focus back on 1
  if [[ "$needs" == *ws2win* ]]; then
    case "$compositor" in
      niri) _binds_guest_niri move-column-to-workspace 2
            _binds_guest_niri focus-workspace 1 ;;
      Hyprland)
        _binds_guest_hyprland \
          "hl.dsp.window.move({ workspace = 2, silent = true })"
        _binds_guest_hyprland "hl.dsp.focus({ workspace = 1 })" ;;
    esac
  fi
  [[ "$needs" == *workspace2* ]] \
    && _binds_guest_go_to_workspace "$compositor" 2
  return 0
}

# _binds_guest_apply_need_tokens <compositor> <needs> — the per-token needs:
# desktop:N, maximized, launch:<app>, clip:<text>.
_binds_guest_apply_need_tokens() {
  local compositor="$1" needs="$2" token
  for token in $needs; do
    case "$token" in
      desktop:*)          # start on workspace/desktop N (grid navigation)
        _binds_guest_go_to_workspace "$compositor" "${token#desktop:}" ;;
      maximized)
        [[ "$compositor" == kwin_wayland ]] && _binds_guest_kwin_run \
          "workspace.activeWindow.setMaximize(true, true);" ;;
      launch:*) setsid -f "${token#launch:}" >/dev/null 2>&1; sleep 4 ;;
      clip:*) printf '%s' "${token#clip:}" | wl-copy >/dev/null 2>&1 ;;
    esac
  done
}

# _binds_guest_focus_for_directory <comp> <dir> — focus a test window that HAS a
# neighbour in <dir>, so a directional focus/move bind can prove it did
# something.
_binds_guest_focus_for_directory() {
  local compositor="$1" direction="$2" pick
  case "$compositor" in
    niri)
      case "$direction" in
        right) _binds_guest_niri focus-column-first ;;
        left)  _binds_guest_niri focus-column-last ;;
        up)    _binds_guest_niri focus-window-bottom ;;
        down)  _binds_guest_niri focus-window-top ;;
      esac ;;
    Hyprland)
      # dwindle with 3 windows: A left half, B top-right, C bottom-right
      pick="$(hyprctl -j clients 2>/dev/null | jq -r --arg c "$FA_BIND_CLASS" \
        --arg d "$direction" '
          [.[] | select(.class == $c and .workspace.id == 1)]
        | (map(.size[1]) | max) as $H
        | (if $d == "right" then min_by(.at[0])
           elif $d == "left" then max_by(.at[0])
           elif $d == "up" then max_by(.at[1])
           else (map(select(.size[1] < $H)) | min_by(.at[1])) end)
        | .address // empty')"
      [[ -n "$pick" ]] \
        && _binds_guest_hyprland \
        "hl.dsp.focus({ window = \"address:$pick\" })" ;;
    kwin_wayland) _binds_guest_kwin_arrange "$direction" ;;
  esac
}

# _binds_guest_kwin_run <js> — run a one-shot KWin script (no JSON IPC on KDE).
_binds_guest_kwin_run() {
  local script id name="fa-kwin-$$-$RANDOM"
  script="$(mktemp --suffix=.js)"
  printf '%s\n' "$1" > "$script"
  id="$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript \
    "$script" "$name" 2>/dev/null)"
  qdbus6 org.kde.KWin "/Scripting/Script${id}" org.kde.kwin.Script.run \
    >/dev/null 2>&1
  sleep 0.5
  qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript \
    "$name" >/dev/null 2>&1
  rm -f "$script"
}

# _binds_guest_kwin_arrange <dir> — tile the two test windows side by side
# (left/ right) or stacked (up/down) and focus the one with a neighbour in
# <dir>.
_binds_guest_kwin_arrange() {
  _binds_guest_kwin_run "
var ws = workspace.windowList().filter(function (w) {
  return w.resourceClass == '$FA_BIND_CLASS'; });
if (ws.length >= 2) {
  var a = workspace.clientArea(KWin.MaximizeArea, workspace.activeScreen,
                               workspace.currentDesktop);
  var d = '$1', h = (d == 'left' || d == 'right');
  ws[0].frameGeometry = {x: a.x, y: a.y,
    width: h ? a.width / 2 : a.width, height: h ? a.height : a.height / 2};
  ws[1].frameGeometry = {x: h ? a.x + a.width / 2 : a.x,
    y: h ? a.y : a.y + a.height / 2,
    width: h ? a.width / 2 : a.width, height: h ? a.height : a.height / 2};
  workspace.activeWindow = (d == 'right' || d == 'down') ? ws[0] : ws[1];
}"
}

# feature_audit_binds_baseline — remember the windows open before the keybind
# phase, so teardown can close whatever a bind opened (launchers, task entries,
# …).
feature_audit_binds_baseline() {
  mkdir -p /tmp/fa-binds
  _binds_guest_windows | jq -r '.[].id | tostring' > /tmp/fa-binds/baseline
}

# feature_audit_binds_teardown — drop the scene: the test windows (recreated per
# bind) and every window a bind opened since the baseline.
feature_audit_binds_teardown() {
  local compositor id
  pkill -f -- "--class $FA_BIND_CLASS" >/dev/null 2>&1 || true
  compositor="$(_binds_guest_compositor)"
  [[ -f /tmp/fa-binds/baseline ]] || { sleep 0.5; return 0; }
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    case "$compositor" in
      niri) niri msg action close-window --id "$id" >/dev/null 2>&1 ;;
      Hyprland) _binds_guest_hyprland \
        "hl.dsp.window.close({ window = \"address:$id\" })" ;;
      kwin_wayland) _binds_guest_kwin_run "workspace.windowList().forEach(
        function (w) { if (w.internalId.toString() == '$id')
          w.closeWindow(); });" ;;
    esac
  done < <(_binds_guest_windows | jq -r --rawfile b /tmp/fa-binds/baseline '
    ($b | split("\n")) as $k
    | .[] | (.id | tostring) as $i | select($k | index($i) | not) | $i')
  sleep 0.5
}

# feature_audit_binds_evaluate <effect> <arg> <before-json> <after-json> — exit
# 0 iff observed.
feature_audit_binds_evaluate() {
  local effect="$1" argument="$2" before="$3" after="$4"
  case "$effect" in
    window-opens) jq -e -n --argjson b "$before" --argjson a "$after" \
      --arg r "$argument" '
        ([$a.windows[] | select(.app | test($r; "i"))] | length)
        > ([$b.windows[] | select(.app | test($r; "i"))] | length)' ;;
    window-closes) jq -e -n --argjson b "$before" --argjson a "$after" \
        '($a.windows | length) < ($b.windows | length)' ;;
    workspace) jq -e -n --argjson b "$before" --argjson a "$after" \
      --argjson n "$argument" \
        '$a.ws.idx == ([$n, $b.ws.count] | min)' ;;
    workspace-changes) jq -e -n --argjson b "$before" --argjson a "$after" \
        '$a.ws.id != $b.ws.id or $a.ws.idx != $b.ws.idx' ;;
    focus-changes) jq -e -n --argjson b "$before" --argjson a "$after" \
        '$a.focused != $b.focused' ;;
    window-changes) jq -e -n --argjson b "$before" --argjson a "$after" \
        '$a.layout != $b.layout or $a.focused != $b.focused' ;;
    layout-changes) jq -e -n --argjson b "$before" --argjson a "$after" \
        '$a.layout != $b.layout' ;;
    screen-changes) jq -e -n --argjson b "$before" --argjson a "$after" \
        '$a.shot != $b.shot and $a.shot != ""' ;;
    file-created) jq -e -n --argjson b "$before" --argjson a "$after" \
        '$a.files > $b.files' ;;
    audio-changes)
      # no sink: can't tell
      [[ -n "$(jq -r .audio <<<"$before")" ]] || return 3
      jq -e -n --argjson b "$before" --argjson a \
        "$after" '$a.audio != $b.audio' ;;
    *) return 2 ;;
  esac >/dev/null
}
