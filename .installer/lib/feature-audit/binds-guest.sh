#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/binds-guest.sh — guest-side keybind state + effects
# =============================================================================
# Staged into the guest and sourced inside the live session (VM Agent Control
# `exec`). The host sends each bind as real input between a `fa_bstate`
# before/after pair, then `fa_beval` judges the declared effect from the two
# snapshots (ADR 0152). Compositor-aware: niri (`niri msg`), Hyprland
# (`hyprctl`), KDE (KWin D-Bus + spectacle).
#
# Effects: window-opens <app-re> | window-closes | workspace <n> |
#   workspace-changes | focus-changes | layout-changes | window-changes
#   (focus or layout) | screen-changes | file-created <dir> | audio-changes |
#   session-ends
# =============================================================================

FA_BIND_CLASS=fa-bind

_fa_comp() {
  local c
  for c in niri Hyprland kwin_wayland; do
    pgrep -x "$c" >/dev/null 2>&1 && { echo "$c"; return; }
  done
  echo none
}

# _fa_windows — normalized window list JSON: [{id, app, ws, focused, geo}].
_fa_windows() {
  case "$(_fa_comp)" in
    niri) niri msg -j windows 2>/dev/null | jq -c 'map({id, app: .app_id,
            ws: .workspace_id, focused: .is_focused,
            geo: {f: .is_floating, l: .layout}})' ;;
    Hyprland) hyprctl -j clients 2>/dev/null | jq -c --arg a \
            "$(hyprctl -j activewindow 2>/dev/null | jq -r '.address // ""')" \
            'map({id: .address, app: .class, ws: .workspace.id,
                  focused: (.address == $a),
                  geo: {at, size, floating, fullscreen}})' ;;
    kwin_wayland) _fa_kwin_windows ;;
    *) echo '[]' ;;
  esac
}

# _fa_kwin_windows — KWin has no JSON IPC; a one-shot KWin script prints the
# window list to the journal, read back by a marker.
_fa_kwin_windows() {
  local m="fa-kwin-$$-$RANDOM" js
  js="$(mktemp --suffix=.js)"
  cat > "$js" <<JS
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
print("$m" + JSON.stringify(out));
JS
  local id
  id="$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript \
    "$js" "$m" 2>/dev/null)"
  qdbus6 org.kde.KWin "/Scripting/Script${id}" \
    org.kde.kwin.Script.run >/dev/null 2>&1
  sleep 0.5
  qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$m" \
    >/dev/null 2>&1
  rm -f "$js"
  journalctl --user -q -o cat --since "-10s" 2>/dev/null \
    | grep -o "$m.*" | tail -1 | sed "s/^$m//" | grep . || echo '[]'
}

# _fa_workspace — {idx, id, count} of the focused output's active workspace.
_fa_workspace() {
  case "$(_fa_comp)" in
    niri) niri msg -j workspaces 2>/dev/null | jq -c '
            (map(select(.is_focused))[0]) as $f
            | {idx: $f.idx, id: $f.id,
               count: (map(select(.output == $f.output)) | length)}' ;;
    # Hyprland creates a numbered workspace on demand: no clamp
    Hyprland) hyprctl -j activeworkspace 2>/dev/null \
            | jq -c '{idx: .id, id: .id, count: 99}' ;;
    kwin_wayland)
      local c n
      c="$(qdbus6 org.kde.KWin /KWin org.kde.KWin.currentDesktop 2>/dev/null)"
      n="$(qdbus6 org.kde.KWin /VirtualDesktopManager \
        org.freedesktop.DBus.Properties.Get org.kde.KWin.VirtualDesktopManager \
        count 2>/dev/null)"
      jq -cn --argjson c "${c:-0}" --argjson n "${n:-0}" \
        '{idx: $c, id: $c, count: $n}' ;;
    *) echo '{}' ;;
  esac
}

_fa_shot_hash() {
  local f; f="$(mktemp --suffix=.png)"
  case "$(_fa_comp)" in
    kwin_wayland) timeout 15 spectacle -bnf -o "$f" >/dev/null 2>&1 ;;
    *) timeout 10 grim "$f" >/dev/null 2>&1 ;;
  esac
  sha1sum "$f" 2>/dev/null | cut -c1-12
  rm -f "$f"
}

_fa_audio() {
  { wpctl get-volume @DEFAULT_AUDIO_SINK@
    wpctl get-volume @DEFAULT_AUDIO_SOURCE@; } \
    2>/dev/null | tr '\n' ' '
}

# fa_bstate [home-rel-dir] — snapshot JSON of everything an effect can
# observe (the dir is where file-created counts new files).
fa_bstate() {
  local dir="$HOME/${1:-Pictures/Screenshots}"
  jq -cn --arg comp "$(_fa_comp)" --argjson w "$(_fa_windows)" \
    --argjson ws "$(_fa_workspace)" --arg shot "$(_fa_shot_hash)" \
    --arg audio "$(_fa_audio)" \
    --arg files "$(find "$dir" -type f 2>/dev/null | wc -l)" '
    { comp: $comp, windows: $w, ws: $ws, shot: $shot, audio: $audio,
      files: ($files | tonumber),
      focused: ([$w[] | select(.focused)][0].id // null),
      layout: ($w | map({id, ws, geo}) | tostring) }'
}

# fa_bsetup <needs> <effect> <arg> — reset to a known scene before a bind: test
# windows on the first workspace (+ a stack / floating / 2nd workspace when
# the bind needs one). Best-effort; the effect check is the judge.
fa_bsetup() {
  local needs="$1" effect="$2" arg="${3:-}" comp n want=2 dir=""
  comp="$(_fa_comp)"
  _fa_act() {
    case "$comp" in
      niri) niri msg action "$@" >/dev/null 2>&1 ;;
      Hyprland) hyprctl dispatch "$@" >/dev/null 2>&1 ;;
    esac
  }
  [[ "$needs" =~ windows:([0-9]+) ]] && want="${BASH_REMATCH[1]}"
  [[ "$needs" =~ dir:([a-z]+) ]] && dir="${BASH_REMATCH[1]}"
  # Hyprland's dwindle needs a third window for a vertical neighbour
  [[ -n "$dir" && "$comp" == Hyprland && "$want" -lt 3 ]] && want=3
  case "$comp" in
    niri) _fa_act focus-workspace 1 ;;
    Hyprland) _fa_act workspace 1 ;;
    kwin_wayland) qdbus6 org.kde.KWin /KWin org.kde.KWin.setCurrentDesktop 1 \
      >/dev/null 2>&1 ;;
  esac
  n="$(_fa_windows | jq --arg c "$FA_BIND_CLASS" '[.[] | select(.app == $c)]
    | length')"
  while ((n < want)); do
    setsid -f kitty --class "$FA_BIND_CLASS" >/dev/null 2>&1
    sleep 1.5; n=$((n + 1))
  done
  [[ "$needs" == *stack* && "$comp" == niri ]] \
    && _fa_act consume-window-into-column
  if [[ "$needs" == *floating* ]]; then
    case "$comp" in
      niri) _fa_act toggle-window-floating ;;
      Hyprland) _fa_act togglefloating ;;
    esac
  fi
  if [[ "$needs" == *ws2win* && "$comp" == Hyprland ]]; then
    _fa_act movetoworkspacesilent 2
  fi
  if [[ "$needs" == *workspace2* ]]; then
    case "$comp" in
      niri) _fa_act focus-workspace 2 ;;
      Hyprland) _fa_act workspace 2 ;;
      kwin_wayland) qdbus6 org.kde.KWin /KWin \
        org.kde.KWin.setCurrentDesktop 2 >/dev/null 2>&1 ;;
    esac
  fi
  local tok
  for tok in $needs; do
    case "$tok" in
      desktop:*)          # start on workspace/desktop N (grid navigation)
        case "$comp" in
          niri) _fa_act focus-workspace "${tok#desktop:}" ;;
          Hyprland) _fa_act workspace "${tok#desktop:}" ;;
          kwin_wayland) qdbus6 org.kde.KWin /KWin \
            org.kde.KWin.setCurrentDesktop "${tok#desktop:}" >/dev/null 2>&1 ;;
        esac ;;
      maximized)
        [[ "$comp" == kwin_wayland ]] && _fa_kwin_run \
          "workspace.activeWindow.setMaximize(true, true);" ;;
      launch:*) setsid -f "${tok#launch:}" >/dev/null 2>&1; sleep 4 ;;
      clip:*) printf '%s' "${tok#clip:}" | wl-copy >/dev/null 2>&1 ;;
    esac
  done
  [[ -n "$dir" ]] && _fa_focus_for_dir "$comp" "$dir"
  # a workspace-N bind must start somewhere else to prove it moved (niri
  # clamps N to the last workspace, so only `1` needs to start further down)
  if [[ "$effect" == workspace && "$arg" == 1 ]]; then
    case "$comp" in
      niri) _fa_act focus-workspace-down ;;
      Hyprland) _fa_act workspace 10 ;;
      kwin_wayland) qdbus6 org.kde.KWin /KWin \
        org.kde.KWin.setCurrentDesktop 2 >/dev/null 2>&1 ;;
    esac
  fi
  sleep 0.5
}

# _fa_focus_for_dir <comp> <dir> — focus a test window that HAS a neighbour
# in <dir>, so a directional focus/move bind can prove it did something.
_fa_focus_for_dir() {
  local comp="$1" dir="$2" pick
  case "$comp" in
    niri)
      case "$dir" in
        right) _fa_act focus-column-first ;;
        left)  _fa_act focus-column-last ;;
        up)    _fa_act focus-window-bottom ;;
        down)  _fa_act focus-window-top ;;
      esac ;;
    Hyprland)
      # dwindle with 3 windows: A left half, B top-right, C bottom-right
      pick="$(hyprctl -j clients 2>/dev/null | jq -r --arg c "$FA_BIND_CLASS" \
        --arg d "$dir" '[.[] | select(.class == $c and .workspace.id == 1)]
        | (map(.size[1]) | max) as $H
        | (if $d == "right" then min_by(.at[0])
           elif $d == "left" then max_by(.at[0])
           elif $d == "up" then max_by(.at[1])
           else (map(select(.size[1] < $H)) | min_by(.at[1])) end)
        | .address // empty')"
      [[ -n "$pick" ]] && _fa_act focuswindow "address:$pick" ;;
    kwin_wayland) _fa_kwin_arrange "$dir" ;;
  esac
}

# _fa_kwin_run <js> — run a one-shot KWin script (no JSON IPC on KDE).
_fa_kwin_run() {
  local js id name="fa-kwin-$$-$RANDOM"
  js="$(mktemp --suffix=.js)"
  printf '%s\n' "$1" > "$js"
  id="$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript \
    "$js" "$name" 2>/dev/null)"
  qdbus6 org.kde.KWin "/Scripting/Script${id}" org.kde.kwin.Script.run \
    >/dev/null 2>&1
  sleep 0.5
  qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript \
    "$name" >/dev/null 2>&1
  rm -f "$js"
}

# _fa_kwin_arrange <dir> — tile the two test windows side by side (left/
# right) or stacked (up/down) and focus the one with a neighbour in <dir>.
_fa_kwin_arrange() {
  _fa_kwin_run "
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

# fa_bteardown — drop the scene's leftovers (floating/stack states and the
# test windows themselves are recreated per bind).
fa_bteardown() {
  pkill -f -- "--class $FA_BIND_CLASS" >/dev/null 2>&1 || true
  sleep 0.5
}

# fa_beval <effect> <arg> <before-json> <after-json> — exit 0 iff observed.
fa_beval() {
  local effect="$1" arg="$2" b="$3" a="$4"
  case "$effect" in
    window-opens) jq -e -n --argjson b "$b" --argjson a "$a" --arg r "$arg" '
        ([$a.windows[] | select(.app | test($r; "i"))] | length)
        > ([$b.windows[] | select(.app | test($r; "i"))] | length)' ;;
    window-closes) jq -e -n --argjson b "$b" --argjson a "$a" \
        '($a.windows | length) < ($b.windows | length)' ;;
    workspace) jq -e -n --argjson b "$b" --argjson a "$a" --argjson n "$arg" \
        '$a.ws.idx == ([$n, $b.ws.count] | min)' ;;
    workspace-changes) jq -e -n --argjson b "$b" --argjson a "$a" \
        '$a.ws.id != $b.ws.id or $a.ws.idx != $b.ws.idx' ;;
    focus-changes) jq -e -n --argjson b "$b" --argjson a "$a" \
        '$a.focused != $b.focused' ;;
    window-changes) jq -e -n --argjson b "$b" --argjson a "$a" \
        '$a.layout != $b.layout or $a.focused != $b.focused' ;;
    layout-changes) jq -e -n --argjson b "$b" --argjson a "$a" \
        '$a.layout != $b.layout' ;;
    screen-changes) jq -e -n --argjson b "$b" --argjson a "$a" \
        '$a.shot != $b.shot and $a.shot != ""' ;;
    file-created) jq -e -n --argjson b "$b" --argjson a "$a" \
        '$a.files > $b.files' ;;
    audio-changes)
      [[ -n "$(jq -r .audio <<<"$b")" ]] || return 3   # no sink: can't tell
      jq -e -n --argjson b "$b" --argjson a "$a" '$a.audio != $b.audio' ;;
    *) return 2 ;;
  esac >/dev/null
}
