#!/usr/bin/env bash
# =============================================================================
# vm/vm-agent.sh — host-side VM Agent Control CLI (ADR 0117)
# =============================================================================
# Drives a persistent-flow Agent-Controllable VM over the harness SSH key so an
# agent can log in to any session, run/screenshot/lock things, and reboot —
# without rediscovering the plumbing each time. Sibling of vm.sh; selects the VM
# the same way (--profile <cat>/<name>) or by domain name (--vm <name>).
#
#   vm-agent.sh [--profile <cat>/<name> | --vm <name>] <verb> [args…]
#
# Verbs (ADR 0117):
#   exec <cmd…>              run a command in the guest with the running
#                            session's env auto-sourced (WAYLAND_DISPLAY, DBUS…)
#   launch <app…>            launch a GUI app detached (never holds the channel)
#   ssh [cmd…]               interactive guest shell (or one-off command)
#   ready [timeout]          block until the session's compositor is up
#   session <niri|hyprland|kde>   switch autologin session + reboot + wait-ready
#   logout                   loginctl terminate-session (fresh re-autologin)
#   reboot                   reboot + wait-ready
#   idle <on|off>            toggle a removable idle/suspend/DPMS inhibitor
#   lock | unlock            loginctl lock-session / unlock-session
#   shot [file]              screenshot (grim on wlroots, spectacle on KDE) →host
#
# SSH uses the harness key (vm/.vm-cache/harness_ed25519, same as the persistent
# flow). Privileged guest steps pipe the harness sudo password (default 12345,
# override VM_AGENT_SUDO_PW). virsh/ssh obey docs/agents/vm-sandbox.md: on a
# `libvirt unreachable (sandbox?)` signal, the agent retries with the sandbox
# disabled.
# =============================================================================

set -Eeuo pipefail

SELF_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$SELF_DIR/.." && pwd)}"
# shellcheck source=../lib/jsonc.sh
source "$INSTALLER_DIR/lib/jsonc.sh"

# CACHE_DIR + key path MUST match flow-persistent.sh so we use the SAME harness
# key it authorized on the guest.
: "${CACHE_DIR:=$SELF_DIR/.vm-cache}"
AGENT_PROFILE_DEFAULT="${VM_AGENT_PROFILE:-desktop/combined}"
AGENT_USER="${VM_AGENT_USER:-aquastias}"
AGENT_SUDO_PW="${VM_AGENT_SUDO_PW:-12345}"
AGENT_READY_TIMEOUT="${VM_AGENT_READY_TIMEOUT:-180}"

die() { echo "vm-agent: $*" >&2; exit 1; }
info() { echo "vm-agent: $*" >&2; }

usage() {
  sed -n '4,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ── pure helpers (unit-tested; no libvirt, no SSH) ───────────────────────────

# agent_key_path — the harness SSH key, identical to flow-persistent's.
agent_key_path() { printf '%s\n' "${CACHE_DIR}/harness_ed25519"; }

# agent_resolve_name <selector> — VM domain name from a --profile ref (read
# .name from the profile jsonc) or a bare --vm name (verbatim).
agent_resolve_name() {
  local kind="$1" ref="$2"
  if [[ "$kind" == vm ]]; then printf '%s\n' "$ref"; return 0; fi
  local file
  if [[ "$ref" == /* && -f "$ref" ]]; then file="$ref"
  else file="$INSTALLER_DIR/vm/profiles/$ref.jsonc"; fi
  [[ -f "$file" ]] || die "profile not found: $file"
  jsonc_strip "$file" | jq -er '.name' \
    || die "profile has no .name: $file"
}

# agent_session_desktop <niri|hyprland|kde> — the DM Session= .desktop id.
agent_session_desktop() {
  case "$1" in
    niri)     printf 'niri.desktop\n' ;;
    hyprland) printf 'hyprland.desktop\n' ;;
    kde)      printf 'plasma.desktop\n' ;;
    *)        return 1 ;;
  esac
}

# agent_session_command <niri|hyprland|kde> — the greetd initial_session command
# (its session launcher; hyprland via start-hyprland, ADR 0070).
agent_session_command() {
  case "$1" in
    niri)     printf 'niri-session\n' ;;
    hyprland) printf 'start-hyprland\n' ;;
    kde)      printf 'startplasma-wayland\n' ;;
    *)        return 1 ;;
  esac
}

# agent_autologin_config <sddm|greetd> <session> <user> — the autologin config
# body for the resolved greeter (ADR 0069/0091). sddm → a drop-in [Autologin]
# block; greetd → an [initial_session] table.
agent_autologin_config() {
  local dm="$1" session="$2" user="$3"
  case "$dm" in
    sddm)
      printf '[Autologin]\nUser=%s\nSession=%s\nRelogin=true\n' \
        "$user" "$(agent_session_desktop "$session")" ;;
    greetd)
      printf '[initial_session]\ncommand = "%s"\nuser = "%s"\n' \
        "$(agent_session_command "$session")" "$user" ;;
    *) return 1 ;;
  esac
}

# agent_shot_tool <compositor> — screenshot tool for the running compositor.
agent_shot_tool() {
  case "$1" in
    kwin_wayland) printf 'spectacle\n' ;;
    niri|Hyprland) printf 'grim\n' ;;
    *) return 1 ;;
  esac
}

# _remote_env_fn — a guest-side bash fragment defining _agent_load_env, which
# finds the running compositor and exports its session environment (read from
# /proc/<pid>/environ) so exec/launch/shot reach the live session.
_remote_env_fn() {
  cat <<'SH'
_agent_load_env() {
  local c comp="" cpid="" client clpid="" src kv sock
  # Identify the running compositor (for tool selection + Qt theme).
  for c in niri Hyprland kwin_wayland; do
    cpid="$(pgrep -x "$c" 2>/dev/null | head -1)"
    if [ -n "$cpid" ]; then comp="$c"; break; fi
  done
  [ -n "$comp" ] || return 1
  AGENT_COMPOSITOR="$comp"
  # Source the session env from a real CLIENT — the compositor *server* has no
  # WAYLAND_DISPLAY of its own. noctalia (wlroots) / plasmashell (KDE).
  # XDG_SESSION_TYPE comes from the client (=wayland), NOT our SSH pty (=tty):
  # a leaked `tty` makes browsers/Electron skip the ScreenCast portal and fall
  # back to internal window-capture (no full-screen), faking a portal failure.
  for client in noctalia plasmashell waybar; do
    clpid="$(pgrep -x "$client" 2>/dev/null | head -1)"
    [ -n "$clpid" ] && break
  done
  src="${clpid:-$cpid}"
  while IFS= read -r -d '' kv; do
    case "$kv" in
      XDG_RUNTIME_DIR=*|WAYLAND_DISPLAY=*|DBUS_SESSION_BUS_ADDRESS=*|\
DISPLAY=*|XAUTHORITY=*|XDG_CURRENT_DESKTOP=*|\
XDG_SESSION_TYPE=*) export "$kv" ;;
    esac
  done < "/proc/$src/environ" 2>/dev/null || true
  # Fallbacks so a server-only source still yields a usable env.
  : "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"; export XDG_RUNTIME_DIR
  if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    sock="$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null \
      | grep -v '\.lock$' | head -1)"
    [ -n "$sock" ] && export WAYLAND_DISPLAY="${sock##*/}"
  fi
  : "${DBUS_SESSION_BUS_ADDRESS:=unix:path=$XDG_RUNTIME_DIR/bus}"
  export DBUS_SESSION_BUS_ADDRESS GDK_BACKEND=wayland
  # Qt platform theme is fleet-set per-compositor for wlroots (ADR 0102); KDE
  # uses its own (plasma-integration), so only default it under niri/Hyprland.
  case "$comp" in niri|Hyprland) : "${QT_QPA_PLATFORMTHEME:=qt6ct}";
    export QT_QPA_PLATFORMTHEME ;; esac
  return 0
}
SH
}

# ── connection (libvirt + ssh) ───────────────────────────────────────────────

_vm_ip() {
  virsh domifaddr "$VM_NAME" 2>/dev/null \
    | awk 'NR>2 { split($4,a,"/"); if (a[1] ~ /^[0-9]/) print a[1] }' | head -1
}

# _preflight — confirm libvirt is reachable and the VM is running, emitting the
# vm-sandbox.md signal so the agent knows to retry with the sandbox disabled.
_preflight() {
  if ! virsh version >/dev/null 2>&1; then
    die "libvirt unreachable (sandbox?) — retry with the sandbox disabled"
  fi
  virsh domstate "$VM_NAME" 2>/dev/null | grep -qx running \
    || die "VM '$VM_NAME' is not running (virsh start it, or check the name)"
}

_ssh() {
  local ip; ip="$(_vm_ip)"
  [[ -n "$ip" ]] || die "no DHCP lease for '$VM_NAME' yet"
  ssh -i "$(agent_key_path)" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR \
    "$AGENT_USER@$ip" "$@"
}

# _ssh_tty — interactive (allocate a TTY).
_ssh_tty() {
  local ip; ip="$(_vm_ip)"
  [[ -n "$ip" ]] || die "no DHCP lease for '$VM_NAME' yet"
  ssh -t -i "$(agent_key_path)" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$AGENT_USER@$ip" "$@"
}

# _sudo <cmd…> — run a privileged guest command, piping the harness pw from the
# host (kept out of the remote argv/process list).
_sudo() {
  printf '%s\n' "$AGENT_SUDO_PW" | _ssh "sudo -S -p '' $*"
}

# _stage <guest-path> — write this function's stdin to a user-writable guest
# path, for staging a file we then install as root.
_stage() { _ssh "cat > '$1'"; }

# _in_session <cmd…> — run a command on the guest inside the live session env.
_in_session() {
  _ssh "bash -s" <<REMOTE
set -e
$(_remote_env_fn)
_agent_load_env || { echo 'vm-agent: no live session on guest' >&2; exit 3; }
$*
REMOTE
}

# ── guest DM detection (for session control) ─────────────────────────────────
_guest_dm() {
  _ssh 'readlink -f /etc/systemd/system/display-manager.service 2>/dev/null' \
    | grep -oE 'sddm|greetd' | head -1
}

# ── verbs ────────────────────────────────────────────────────────────────────

verb_ready() {
  local timeout="${1:-$AGENT_READY_TIMEOUT}" elapsed=0
  info "waiting for a session on '$VM_NAME' (≤${timeout}s)…"
  while ((elapsed < timeout)); do
    if _ssh 'pgrep -x niri >/dev/null 2>&1 || pgrep -x Hyprland \
      >/dev/null 2>&1 || pgrep -x kwin_wayland >/dev/null 2>&1' 2>/dev/null
    then info "session up."; return 0; fi
    sleep 5; elapsed=$((elapsed + 5))
  done
  die "timed out waiting for a session on '$VM_NAME'"
}

verb_exec() {
  (($#)) || die "exec needs a command"
  _in_session "$*"
}

verb_launch() {
  (($#)) || die "launch needs an app"
  _in_session "setsid -f $* </dev/null >/dev/null 2>&1"
  info "launched: $*"
}

verb_ssh() {
  if (($#)); then _ssh_tty "$@"; else _ssh_tty; fi
}

verb_reboot() {
  info "rebooting '$VM_NAME'…"
  _sudo systemctl reboot || true
  sleep 8
  verb_ready
}

verb_logout() {
  # Terminate ONLY the graphical (seat0) session — never the agent's own SSH
  # session (which has no seat). Relogin autologins a fresh graphical session.
  info "logging out (terminating the graphical session)…"
  local gid
  gid="$(_ssh "loginctl list-sessions --no-legend \
    | awk '\$4==\"seat0\"{print \$1; exit}'")"
  [[ -n "$gid" ]] || die "no graphical (seat0) session to terminate"
  _sudo "loginctl terminate-session $gid" || true
  sleep 6
  verb_ready
}

verb_session() {
  local target="${1:-}"
  agent_session_desktop "$target" >/dev/null \
    || die "session must be niri|hyprland|kde"
  local dm; dm="$(_guest_dm)"
  [[ -n "$dm" ]] || die "could not detect the guest display manager"
  local cfg; cfg="$(agent_autologin_config "$dm" "$target" "$AGENT_USER")"
  info "setting $dm autologin → $target, then rebooting…"
  case "$dm" in
    sddm)
      # A CLI-owned drop-in, named to sort LAST in /etc/sddm.conf.d so it wins:
      # sddm merges alphabetically (last wins), and the seeded kde_settings.conf
      # (empty Autologin) sorts after a 99-* name ('9' < 'k'), so use zz-*.
      printf '%s\n' "$cfg" | _stage /tmp/vm-agent-autologin.conf
      _sudo "install -Dm0644 /tmp/vm-agent-autologin.conf \
        /etc/sddm.conf.d/zz-agent-autologin.conf"
      _ssh "rm -f /tmp/vm-agent-autologin.conf" || true ;;
    greetd)
      # Rewrite greetd's [initial_session] table, keeping the rest of the file.
      { printf '%s\n' "$cfg"; } | _stage /tmp/vm-agent-greetd-block
      _stage /tmp/vm-agent-greetd.py <<'PY'
import re, sys
p = "/etc/greetd/config.toml"
block = open("/tmp/vm-agent-greetd-block").read().rstrip() + "\n"
s = open(p).read()
if "[initial_session]" in s:
    s = re.sub(r"(?ms)^\[initial_session\].*?(?=^\[|\Z)", block, s)
else:
    s = s.rstrip() + "\n\n" + block
open(p, "w").write(s)
PY
      _sudo "python3 /tmp/vm-agent-greetd.py"
      _ssh "rm -f /tmp/vm-agent-greetd.py /tmp/vm-agent-greetd-block" || true ;;
  esac
  verb_reboot
}

verb_idle() {
  local state="${1:-}"
  case "$state" in
    off)
      # Removable inhibitor: a detached logind idle/sleep hold (covers
      # suspend/DPMS) + Noctalia caffeine (covers the wlroots compositor lock,
      # ADR 0100). Both are reversible by `idle on` — nothing is provisioned off.
      _in_session "setsid -f systemd-inhibit \
        --what=idle:sleep:handle-lid-switch --who=vm-agent \
        --why=agent-driving --mode=block sleep infinity \
        </dev/null >/dev/null 2>&1 || true; \
        command -v noctalia >/dev/null 2>&1 && noctalia msg caffeine-enable \
        >/dev/null 2>&1 || true"
      info "idle inhibited (reversible)." ;;
    on)
      _in_session "pkill -f 'systemd-inhibit .*who=vm-agent' 2>/dev/null; \
        command -v noctalia >/dev/null 2>&1 && noctalia msg caffeine-disable \
        >/dev/null 2>&1 || true"
      info "idle restored." ;;
    *) die "idle needs on|off" ;;
  esac
}

verb_lock()   { _sudo "loginctl lock-sessions";   info "locked."; }
verb_unlock() { _sudo "loginctl unlock-sessions"; info "unlocked."; }

verb_shot() {
  local out="${1:-vm-agent-shot.png}"
  local guest_png="/tmp/vm-agent-shot.$$.png"
  # Detect compositor, wake the display, capture with the right tool.
  _in_session "
    (command -v noctalia >/dev/null && noctalia msg dpms-on) 2>/dev/null || true
    tool=\$(case \"\$AGENT_COMPOSITOR\" in
      kwin_wayland) echo spectacle;; niri|Hyprland) echo grim;; esac)
    case \"\$tool\" in
      grim)      timeout 12 grim '$guest_png' ;;
      spectacle) timeout 15 spectacle -bnf -o '$guest_png' ;;
      *) echo 'vm-agent: unknown compositor, cannot screenshot' >&2; exit 4 ;;
    esac" || die "screenshot failed (display asleep or render stalled?)"
  local ip; ip="$(_vm_ip)"
  scp -i "$(agent_key_path)" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    "$AGENT_USER@$ip:$guest_png" "$out" >/dev/null \
    || die "failed to pull screenshot"
  _ssh "rm -f '$guest_png'" || true
  info "screenshot → $out"
}

# ── main ─────────────────────────────────────────────────────────────────────

main() {
  local sel_kind=profile sel_ref="$AGENT_PROFILE_DEFAULT"
  while (($#)); do
    case "$1" in
      --profile) sel_kind=profile; sel_ref="${2:-}"; shift 2 ;;
      --profile=*) sel_kind=profile; sel_ref="${1#*=}"; shift ;;
      --vm) sel_kind=vm; sel_ref="${2:-}"; shift 2 ;;
      --vm=*) sel_kind=vm; sel_ref="${1#*=}"; shift ;;
      --user) AGENT_USER="${2:-}"; shift 2 ;;
      --help|-h) usage; return 0 ;;
      --) shift; break ;;
      -*) usage >&2; die "unknown option '$1'" ;;
      *) break ;;
    esac
  done

  local verb="${1:-}"; shift || true
  [[ -n "$verb" ]] || { usage >&2; die "a verb is required"; }

  VM_NAME="$(agent_resolve_name "$sel_kind" "$sel_ref")"

  case "$verb" in
    exec|launch|ssh|ready|session|logout|reboot|idle|lock|unlock|shot) ;;
    *) usage >&2; die "unknown verb '$verb'" ;;
  esac

  _preflight
  "verb_${verb}" "$@"
}

# Source-guard so the bats suite can source and call the pure helpers.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi
