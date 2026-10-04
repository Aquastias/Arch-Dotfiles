#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/live.sh — the live Audit Run (ADR 0152)
# =============================================================================
# One VM at a time: install each Audit Variant through the persistent VM
# Harness flow, boot it with our own serial capture + Console Answerer (so
# encrypted boots unlock and every boot is observed), drive it with VM Agent
# Control, and drop raw artifacts into <run>/<variant>/<phase>/ for `report`.
# Collection never judges; a fatal failure (no install, no boot) is written
# as a `fatal.lines` artifact and the run moves on to the next variant.
#
# Needs libvirt; per docs/agents/vm-sandbox.md run it with the sandbox off.
# =============================================================================

# shellcheck source=../../vm/lib/core.sh
[[ "$(type -t _vm_running)" == function ]] \
  || source "$INSTALLER_DIR/vm/lib/core.sh"
# shellcheck source=../../vm/lib/console-answerer.sh
source "$INSTALLER_DIR/vm/lib/console-answerer.sh"

: "${CACHE_DIR:=$INSTALLER_DIR/vm/.vm-cache}"
: "${HTTP_PORT:=9876}"
: "${FA_BOOT_TIMEOUT_SEC:=900}"
: "${FA_SETTLE_SEC:=90}"
export CACHE_DIR

FA_AGENT="$INSTALLER_DIR/vm/vm-agent.sh"
FA_ANSWER_PID=""

fa_runs_root() {
  printf '%s\n' "${FEATURE_AUDIT_RUNS:-$INSTALLER_DIR/.audit-runs}"
}

# fa_agent <verb> [args…] — VM Agent Control on the audit VM as its user.
# stdin reaches the guest only for a stdin-script `sudo`; every other call
# gets /dev/null, or ssh would swallow the caller's `while read` input.
fa_agent() {
  if [[ "$1" == sudo && $# -eq 1 ]]; then
    bash "$FA_AGENT" --vm "$VM_NAME" --user "$FA_USER" "$@"
  else
    bash "$FA_AGENT" --vm "$VM_NAME" --user "$FA_USER" "$@" </dev/null
  fi
}

# fa_fatal <phase-dir> <message> — record a fatal Finding for this phase.
fa_fatal() {
  mkdir -p "$1"
  printf '%s\n' "$2" >> "$1/fatal.lines"
  warn "FATAL: $2"
}

# fa_stage_repo — serve the committed HEAD to the guest (dumb-HTTP bare repo
# under the harness HTTP root), so the audit tests local commits without a
# push. Uncommitted changes are NOT audited.
fa_stage_repo() {
  local top dst
  top="$(git -C "$INSTALLER_DIR" rev-parse --show-toplevel)"
  dst="$CACHE_DIR/feature-audit-repo.git"
  [[ -z "$(git -C "$top" status --porcelain --untracked-files=no)" ]] \
    || warn "Uncommitted changes are NOT audited (the guest clones HEAD)." >&2
  rm -rf "$dst"
  git clone -q --bare "$top" "$dst"
  git -C "$dst" repack -a -d -q
  git -C "$dst" update-server-info
  printf 'http://%s:%s/feature-audit-repo.git\n' "$LIBVIRT_GATEWAY" \
    "$HTTP_PORT"
}

# fa_wait_ssh <timeout> — until the guest's sshd answers for the audit user.
fa_wait_ssh() {
  local t="$1" e=0 ip
  while ((e < t)); do
    ip="$(_vm_ip_now)"
    if [[ -n "$ip" ]] && fa_agent sudo true >/dev/null 2>&1; then
      return 0
    fi
    sleep 5; e=$((e + 5))
  done
  return 1
}

# fa_serial_start <log> — capture serial + answer disk-unlock prompts for the
# whole time the domain runs (survives guest reboots).
fa_serial_start() {
  local log="$1" dev
  _start_console_capture "$log" >/dev/null
  dev="$(virsh ttyconsole "$VM_NAME" 2>/dev/null)" || dev=""
  if [[ -n "$dev" ]]; then
    console_answerer_watch "$log" "$dev" &
    FA_ANSWER_PID=$!
  fi
}

fa_serial_stop() {
  _stop_console_capture
  [[ -n "$FA_ANSWER_PID" ]] || return 0
  kill "$FA_ANSWER_PID" 2>/dev/null || true
  wait "$FA_ANSWER_PID" 2>/dev/null || true
  FA_ANSWER_PID=""
}

# fa_vm_start <phase-dir> — power the domain on behind the host-capacity
# guard (ADR 0099); a refusal is this variant's fatal, not the run's.
fa_vm_start() {
  if ! ( _vm_capacity_preflight ) >/dev/null 2>&1; then
    fa_fatal "$1" "host capacity: ${VM_RAM_MB:-?} MiB VM refused"
    return 1
  fi
  mkdir -p "$1"
  # "already running" is fine; any error is kept as boot-fatal evidence.
  virsh start "$VM_NAME" >/dev/null 2>"$1/virsh-start.err" || true
  [[ -s "$1/virsh-start.err" ]] || rm -f "$1/virsh-start.err"
}

# fa_boot_evidence <phase-dir> — on a boot fatal, keep what the host still
# sees: the domain state and the VGA console (the serial log can be empty).
fa_boot_evidence() {
  mkdir -p "$1"
  virsh domstate --reason "$VM_NAME" > "$1/domstate.txt" 2>&1 || true
  virsh screenshot "$VM_NAME" "$1/console.png" >/dev/null 2>&1 || true
}

# fa_wait_until <cap-sec> <guest-check> — poll a root shell check on the
# guest every 5s; return once it holds twice in a row, or at the cap. The
# readiness form of a fixed settle: a quiet guest is judged at once, a busy
# one still gets the old full wait.
fa_wait_until() {
  local cap="$1" check="$2" end=$((SECONDS + $1)) ok=0
  # wall clock, not the sleeps: a slow guest check counts toward the cap
  while ((SECONDS < end)); do
    if fa_agent sudo <<<"$check" >/dev/null 2>&1; then
      ok=$((ok + 1)); ((ok >= 2)) && return 0
    else ok=0; fi
    sleep 5
  done
}

# Settled: no systemd job queued and the boot has left `starting`.
_FA_SETTLED='[ -z "$(systemctl list-jobs --no-legend)" ] &&
  ! systemctl is-system-running 2>/dev/null | grep -qxE "starting|initializing"'
# …and no unit still activating (the timer soak's delayed work).
_FA_NONE_ACTIVATING='[ -z "$(systemctl list-units --state=activating \
  --no-legend)" ]'

# fa_boot <phase-dir> — power on the installed system and wait for SSH.
fa_boot() {
  local dir="$1"
  mkdir -p "$dir"
  fa_vm_start "$dir" || return 1
  fa_serial_start "$dir/serial.log"
  fa_wait_ssh "$FA_BOOT_TIMEOUT_SEC" || {
    fa_boot_evidence "$dir"
    fa_fatal "$dir" \
      "installed system never reached SSH (${FA_BOOT_TIMEOUT_SEC}s)"
    return 1
  }
  fa_wait_until "$FA_SETTLE_SEC" "$_FA_SETTLED"
}

_FA_BOOT_ID=/proc/sys/kernel/random/boot_id

# fa_await_new_boot <phase-dir> <old-boot-id> — wait for the guest to come
# back as a new boot. The VM's virgl GPU can stall, leaving GPU clients in D
# state so shutdown never ends (a host artefact, not the product): after the
# grace, hard-reset the domain and record it in vm-reset.txt.
fa_await_new_boot() {
  local dir="$1" old="$2" id e=0 down=0
  while ((e < ${FA_SHUTDOWN_GRACE_SEC:-240})); do
    sleep 10; e=$((e + 10))
    id="$(fa_agent sudo cat "$_FA_BOOT_ID" 2>/dev/null)" || { id=""; down=1; }
    # an unknown old id: trust an id only once the guest has been down
    if [[ -n "$id" && "$id" != "$old" ]] && { [[ -n "$old" ]] || ((down)); }
    then return 0; fi
  done
  virsh reset "$VM_NAME" >/dev/null 2>&1 || true
  mkdir -p "$dir"
  printf 'reboot wedged in shutdown for %ss (virgl GPU stall); reset\n' \
    "${FA_SHUTDOWN_GRACE_SEC:-240}" >> "$dir/vm-reset.txt"
}

# fa_reboot <phase-dir> — guest reboot, wait for SSH, settle. The serial
# capture + answerer keep running across the reboot.
fa_reboot() {
  local dir="$1" old
  mkdir -p "$dir"
  old="$(fa_agent sudo cat "$_FA_BOOT_ID" 2>/dev/null)" || old=""
  fa_agent sudo systemctl reboot >/dev/null 2>&1 || true
  fa_await_new_boot "$dir" "$old"
  fa_wait_ssh "$FA_BOOT_TIMEOUT_SEC" || {
    fa_boot_evidence "$dir"
    fa_fatal "$dir" "no SSH after reboot (${FA_BOOT_TIMEOUT_SEC}s)"
    return 1
  }
  fa_wait_until "$FA_SETTLE_SEC" "$_FA_SETTLED"
}

# _fa_collect_script [since-epoch] — guest-side (root) signal collector.
# With a since-epoch only that window's journal/coredumps are taken, so an
# in-boot phase reports its own lines, not the whole boot's again.
_fa_collect_script() {
  printf 'SINCE=%q\n' "${1:-}"
  cat <<'SH'
set -u
o=/tmp/fa-collect
rm -rf "$o"; mkdir -p "$o"
win=(-b); [ -n "$SINCE" ] && win=(-b --since "@$SINCE")
systemctl --failed --plain --no-legend --no-pager \
  > "$o/failed-units-system.lines" 2>&1
for u in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $2}'); do
  systemctl --user -M "$u@" --failed --plain --no-legend --no-pager \
    > "$o/failed-units-user-$u.lines" 2>/dev/null || true
done
# system journal (services + kernel) and each user's own, as separate sources
journalctl "${win[@]}" --system -p warning --no-pager -q -o short \
  > "$o/journal.lines" 2>&1
for u in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
  n="$(id -nu "$u" 2>/dev/null)" || continue
  journalctl "${win[@]}" _UID="$u" -p warning --no-pager -q -o short \
    > "$o/journal-user-$n.lines" 2>&1
done
cw=(); [ -n "$SINCE" ] && cw=(--since "@$SINCE")
coredumpctl list "${cw[@]}" --no-legend --no-pager -q \
  > "$o/coredumps.lines" 2>/dev/null || true
chmod -R a+rX "$o"
SH
}

# fa_guest_now — the guest's epoch (phase windows are guest-clock based).
fa_guest_now() { fa_agent sudo date +%s 2>/dev/null | tr -dc 0-9; }

# fa_pull_into <guest-dir> <host-dir> — pull a guest dir's files flat.
fa_pull_into() {
  local tmp; tmp="$(mktemp -d)"
  if fa_agent pull "$1" "$tmp" >/dev/null 2>&1; then
    mkdir -p "$2"
    cp -rf "$tmp/${1##*/}/." "$2/" 2>/dev/null || true
    rm -rf "$tmp"; return 0
  fi
  rm -rf "$tmp"; return 1
}

# fa_collect <phase-dir> [since-epoch] — harvest signals for the phase.
fa_collect() {
  local dir="$1"
  mkdir -p "$dir"
  _fa_collect_script "${2:-}" | fa_agent sudo >/dev/null 2>&1 \
    || { fa_fatal "$dir" "collector failed to run in the guest"; return 1; }
  fa_pull_into /tmp/fa-collect "$dir" \
    || fa_fatal "$dir" "could not pull collected artifacts"
}

# ── later phases (feature-audit/07) ──────────────────────────────────────────

# _fa_timers_script — start every enabled timer's unit once (bounded), so
# delayed work (reflector, freshclam, snapshots, fwupd) fails now, not later.
_fa_timers_script() {
  cat <<'SH'
set -u
for t in $(systemctl list-timers --all --no-legend --plain \
    | awk '{for (i=1;i<=NF;i++) if ($i ~ /\.timer$/) {print $i; break}}'); do
  u="$(systemctl show -p Unit --value "$t")"
  [ -n "$u" ] || continue
  if timeout 900 systemctl start "$u" >/dev/null 2>&1; then
    # a unit Condition* skip also "starts" fine: say it never ran
    if [ "$(systemctl show -p ConditionResult --value "$u")" = no ]; then
      echo "SKIP timer-$t $u skipped: its unit condition is unmet"
    else echo "PASS timer-$t started $u"; fi
  else
    echo "FAIL timer-$t $u failed or timed out"
  fi
done
SH
}

# fa_phase_timers <variant-dir> — force timers, soak, collect.
fa_phase_timers() {
  local dir="$1/timers" since
  mkdir -p "$dir"
  since="$(fa_guest_now)"
  _fa_timers_script | fa_agent sudo > "$dir/probe-timers@root.probe" 2>&1 \
    || true
  # soak: delayed work the forced timers queued finishes (or fails) now
  fa_wait_until "${FA_SOAK_SEC:-600}" "$_FA_SETTLED && $_FA_NONE_ACTIVATING"
  fa_collect "$dir" "$since"
}

# _fa_boot2_prep_script <user> — plant rollback/persistence markers and
# record identity that must survive the reboot.
_fa_boot2_prep_script() {
  printf 'U=%q\n' "$1"
  cat <<'SH'
set -u
echo fa > /etc/fa-rollback-probe
h="$(getent passwd "$U" | cut -d: -f6)"
if [ -n "$h" ]; then
  echo fa > "$h/.fa-persist-probe"; chown "$U" "$h/.fa-persist-probe"
fi
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null \
  | awk '{print $2}' > /var/tmp/fa-hostkey
cp /var/tmp/fa-hostkey "$h/.fa-hostkey" 2>/dev/null || true
SH
}

# _fa_boot2_check_script <user> <impermanent> <sops> — the reboot proofs.
_fa_boot2_check_script() {
  cat "$INSTALLER_DIR/lib/feature-audit/probe-lib.sh"
  printf 'U=%q IMP=%q SOPS=%q\n' "$1" "$2" "$3"
  cat <<'SH'
set -u

h="$(getent passwd "$U" | cut -d: -f6)"
if [ "$IMP" = true ]; then
  [ -e /etc/fa-rollback-probe ] \
    && fa_fail rollback "/etc marker survived reboot (not rolled back)" \
    || fa_pass rollback "/etc rolled back"
fi
[ -e "$h/.fa-persist-probe" ] && fa_pass home-persist "home kept" \
  || fa_fail home-persist "home marker lost on reboot"
now="$(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null \
  | awk '{print $2}')"
[ -n "$now" ] && [ "$now" = "$(cat "$h/.fa-hostkey" 2>/dev/null)" ] \
  && fa_pass ssh-hostkey "host key stable" \
  || fa_fail ssh-hostkey "ssh host key changed across reboot"
if [ "$SOPS" = true ]; then
  systemctl is-active --quiet sops-runtime.service \
    && fa_pass sops-runtime "decrypted on boot" \
    || fa_fail sops-runtime "sops-runtime.service not active after reboot"
fi
rm -f "$h/.fa-persist-probe" "$h/.fa-hostkey" /etc/fa-rollback-probe
SH
}

# fa_phase_boot2 <variant-dir> <cfg> — reboot and prove what must survive.
fa_phase_boot2() {
  local dir="$1/boot2" cfg="$2" imp sops
  mkdir -p "$dir"
  imp="$(jq -r '.options.impermanence.enabled // false' <<<"$cfg")"
  sops="$(jq -r 'if (.options.age_key_url // "") != "" then true
                 else false end' <<<"$cfg")"
  _fa_boot2_prep_script "$FA_USER" | fa_agent sudo >/dev/null 2>&1 || true
  fa_reboot "$dir" || return 1
  _fa_boot2_check_script "$FA_USER" "$imp" "$sops" \
    | fa_agent sudo > "$dir/probe-boot@root.probe" 2>&1 || true
  fa_collect "$dir"
}

# fa_phase_power <variant-dir> — ACPI suspend-to-RAM and wake (the VM is
# created with S3/S4, VM_PM): the guest suspends itself, the host waits for
# `pmsuspended`, wakes it and proves it came back. Hibernation needs a
# resume device the guest may not have; the probe says why when skipped.
fa_phase_power() {
  local dir="$1/power" out since st=""
  out="$dir/probe-power@root.probe"
  mkdir -p "$dir"
  since="$(fa_guest_now)"
  fa_agent sudo "systemd-run --on-active=5 systemctl suspend" >/dev/null 2>&1
  for _ in $(seq 30); do
    st="$(virsh domstate "$VM_NAME" 2>/dev/null)"
    [[ "$st" == pmsuspended ]] && break
    sleep 2
  done
  if [[ "$st" != pmsuspended ]]; then
    echo "FAIL power-suspend guest never reached S3 (domstate: $st)" >> "$out"
  else
    echo "PASS power-suspend guest entered S3" >> "$out"
    virsh dompmwakeup "$VM_NAME" >/dev/null 2>&1
    if fa_wait_ssh 180; then
      echo "PASS power-resume guest woke and answers SSH" >> "$out"
    else
      echo "FAIL power-resume guest did not come back from S3" >> "$out"
      return 1
    fi
  fi
  fa_agent sudo "sh -c 'swapon --show=NAME --noheadings; \
    cat /sys/power/state /sys/power/disk'" > "$dir/power-state.txt" 2>&1
  if grep -qw disk "$dir/power-state.txt" \
     && fa_agent sudo "sh -c 'grep -q resume= /proc/cmdline'" >/dev/null 2>&1
  then
    # S4: the VM powers off; starting it again must RESUME (same boot id)
    local bid; bid="$(fa_agent sudo cat /proc/sys/kernel/random/boot_id)"
    fa_agent sudo "systemd-run --on-active=5 systemctl hibernate" \
      >/dev/null 2>&1
    for _ in $(seq 90); do
      [[ "$(virsh domstate "$VM_NAME" 2>/dev/null)" == "shut off" ]] && break
      sleep 2
    done
    fa_serial_stop   # capture ended with the power-off; unlock needs it back
    fa_vm_start "$dir" || return 1
    fa_serial_start "$dir/serial.log"
    if ! fa_wait_ssh "$FA_BOOT_TIMEOUT_SEC"; then
      echo "FAIL power-hibernate no SSH after resume" >> "$out"; return 1
    fi
    if [[ "$(fa_agent sudo cat /proc/sys/kernel/random/boot_id)" == "$bid" ]]
    then echo "PASS power-hibernate resumed from S4" >> "$out"
    else echo "FAIL power-hibernate booted fresh instead of resuming" >> "$out"
    fi
  else
    echo "SKIP power-hibernate no resume device configured" \
      "(ZFS swap on a zvol cannot hibernate)" >> "$out"
  fi
  fa_collect "$dir" "$since"
}

# fa_phase_upgrade <variant-dir> — full upgrade, reboot, collect.
fa_phase_upgrade() {
  local dir="$1/upgrade"
  mkdir -p "$dir"
  fa_agent sudo "pacman -Syu --noconfirm 2>&1" > "$dir/pacman.log" 2>&1 \
    || fa_fatal "$dir" "pacman -Syu failed (see pacman.log)"
  fa_reboot "$dir" || return 1
  fa_collect "$dir"
}

# ── sessions (feature-audit/08) ──────────────────────────────────────────────

# fa_desktops <cfg> — the variant's desktop set, one per line.
fa_desktops() {
  jq -r '.environment.desktop // [] | if type == "string" then [.] else . end
    | .[]' <<<"$1"
}

# _fa_session_logs_script <user> — compositor/session logs the journal lacks
# (Hyprland's own log, the DM's wayland-session log) into /tmp/fa-logs.
_fa_session_logs_script() {
  printf 'U=%q\n' "$1"
  cat <<'SH'
set -u
o=/tmp/fa-logs; rm -rf "$o"; mkdir -p "$o"
uid="$(id -u "$U")"; h="$(getent passwd "$U" | cut -d: -f6)"
for f in /run/user/"$uid"/hypr/*/hyprland.log; do
  [ -f "$f" ] && cp "$f" "$o/hyprland.log"
done
[ -f "$h/.local/share/sddm/wayland-session.log" ] \
  && cp "$h/.local/share/sddm/wayland-session.log" "$o/wayland-session.log"
[ -f "$h/.local/share/sddm/xorg-session.log" ] \
  && cp "$h/.local/share/sddm/xorg-session.log" "$o/xorg-session.log"
chmod -R a+rX "$o"
SH
}

# _fa_session_client <desktop> <cfg> — the shell process a session brings up
# (empty: none expected, a stock or shell-less wlroots session).
_fa_session_client() {
  [[ "$1" == kde ]] && { echo plasmashell; return; }
  jq -r 'if .environment.stock == true then empty
    else (.environment.wayland_shell // "noctalia")
      | select(. != "none") end' <<<"$2"
}

# _fa_session_settled <user> <client> — guest check: the shell client (if
# any) runs and the user manager has no job queued.
_fa_session_settled() {
  local u="$1" c="$2"
  printf '%s' "${c:+pgrep -u $u -x $c >/dev/null && }"
  printf '[ -z "$(runuser -u %s -- env XDG_RUNTIME_DIR=/run/user/$(id -u %s)' \
    "$u" "$u"
  printf ' systemctl --user list-jobs --no-legend)" ]'
}

# fa_phase_sessions <variant-dir> <cfg> — log into each compositor of the set
# (one phase dir per desktop), collect its window, screenshot it.
fa_phase_sessions() {
  local vdir="$1" cfg="$2" de dir since app
  while IFS= read -r de; do
    [[ -n "$de" ]] || continue
    dir="$vdir/sessions-$de"
    mkdir -p "$dir/screens"
    since="$(fa_guest_now)"
    if ! fa_agent session "$de" > "$dir/agent.txt" 2>&1; then
      echo "session $de did not become ready (see agent.txt)" \
        >> "$dir/session-start.lines"
      fa_collect "$dir" "$since"
      continue
    fi
    fa_agent idle off >/dev/null 2>&1 || true
    fa_wait_until "${FA_SESSION_SETTLE_SEC:-45}" "$(_fa_session_settled \
      "$FA_USER" "$(_fa_session_client "$de" "$cfg")")"
    fa_agent shot "$dir/screens/session-$de.png" >> "$dir/agent.txt" 2>&1 \
      || echo "session $de: screenshot failed" >> "$dir/session-start.lines"
    fa_collect "$dir" "$since"
    _fa_session_logs_script "$FA_USER" | fa_agent sudo >/dev/null 2>&1 \
      && fa_pull_into /tmp/fa-logs "$dir" || true
    # desktop probes (extras/desktop/<de>/audit.sh) in this very session
    if [[ -f "$INSTALLER_DIR/extras/desktop/$de/audit.sh" ]] \
       && fa_stage_probes "$cfg" "$INSTALLER_DIR/extras/desktop/$de"; then
      fa_run_probes "$dir" "sessions-$de" 1 "$cfg" "$FA_USER"
    fi
    # toolkit screenshots for visual review (ADR 0117: Qt → Dolphin, GTK →
    # nm-connection-editor)
    for app in dolphin nm-connection-editor; do
      fa_agent launch "$app" >/dev/null 2>&1 || continue
      sleep 5
      fa_agent shot "$dir/screens/$de-$app.png" >> "$dir/agent.txt" 2>&1
      fa_agent sudo "pkill -x $app" >/dev/null 2>&1 || true
    done
  done < <(fa_desktops "$cfg")
}

# ── probes (feature-audit/09, 10) ────────────────────────────────────────────

# fa_probe_dirs — every program dir shipping an audit probe.
fa_probe_dirs() {
  local d
  for d in "$INSTALLER_DIR"/programs/*/*/; do
    [[ -f "$d/audit.sh" ]] && printf '%s\n' "${d%/}"
  done
}

# fa_stage_probes <cfg> <dir…> — push probes + helper lib + the variant's
# config to the guest's /tmp/fa-probes.
fa_stage_probes() {
  local cfg="$1" tmp d n; shift
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/fa-probes"
  cp "$INSTALLER_DIR/lib/feature-audit/probe-lib.sh" "$tmp/fa-probes/_lib.sh"
  printf '%s\n' "$cfg" > "$tmp/fa-probes/config.json"
  for d in "$@"; do
    n="${d##*/}"
    mkdir -p "$tmp/fa-probes/$n"
    cp "$d/audit.sh" "$tmp/fa-probes/$n/"
    [[ -f "$d/audit-binds.jsonc" ]] \
      && cp "$d/audit-binds.jsonc" "$tmp/fa-probes/$n/"
    [[ -d "$d/audit-fixtures" ]] \
      && cp -rL "$d/audit-fixtures" "$tmp/fa-probes/$n/"
    # program-driven keybinds (nvim …): the matched plan rides along
    local s
    for s in $(fa_binds_program_sources "$n"); do
      fa_binds_plan "$s" >> "$tmp/fa-probes/$n/binds-plan.jsonl"
      # the probe plans binds only its live dump sees with the same matcher
      cp "$INSTALLER_DIR/lib/feature-audit/binds-plan.jq" "$tmp/fa-probes/$n/"
    done
  done
  fa_agent sudo "rm -rf /tmp/fa-probes" >/dev/null 2>&1 || true
  fa_agent push "$tmp/fa-probes" /tmp >/dev/null 2>&1
  local rc=$?
  rm -rf "$tmp"
  return "$rc"
}

# _fa_probe_runner_script <phase> <online> <accounts…> — run every staged
# probe once per account (root + each variant user), in that user's session
# env when one is live, into /tmp/fa-probe-out.
_fa_probe_runner_script() {
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

# fa_run_probes <phase-dir> <phase> <online> <cfg> [account…] — run the
# staged probes (default accounts: root + every variant user), pull output.
fa_run_probes() {
  local dir="$1" phase="$2" online="$3" cfg="$4"; shift 4
  local -a accts=("$@")
  if ((${#accts[@]} == 0)); then
    mapfile -t accts < <(jq -r '.users[]?' <<<"$cfg")
    accts=(root "${accts[@]}")
  fi
  # a failed runner still leaves every finished probe's output: pull it
  _fa_probe_runner_script "$phase" "$online" "${accts[@]}" \
    | fa_agent sudo >/dev/null 2>&1 \
    || fa_fatal "$dir" "probe runner failed in the guest"
  fa_pull_into /tmp/fa-probe-out "$dir" \
    || fa_fatal "$dir" "could not pull probe output"
}

# fa_phase_probes <variant-dir> <cfg> — every program probe offline (guest
# internet cut, SSH kept), then online: a check that only passes online is a
# runtime fetch (the feature was not fully set up at install).
fa_phase_probes() {
  local vdir="$1" cfg="$2" since sel kind d ph
  local -a dirs all skips=()
  mapfile -t all < <(fa_probe_dirs)
  # Probe Gate: a program this variant does not select is SKIPped, not judged
  sel="$(fa_selected_programs "$cfg")"
  while IFS=$'\t' read -r kind d; do
    if [[ "$kind" == run ]]; then dirs+=("$d"); else skips+=("$d"); fi
  done < <(fa_probe_gate_split "$sel" "${all[@]}")
  for ph in probes-offline probes-online; do
    mkdir -p "$vdir/$ph"
    for d in "${skips[@]}"; do
      printf 'SKIP %s-selected not selected in this variant (Probe Gate)\n' \
        "$d" > "$vdir/$ph/probe-$d@gate.probe"
    done
  done
  ((${#dirs[@]})) || return 0
  fa_stage_probes "$cfg" "${dirs[@]}" \
    || { fa_fatal "$vdir/probes-offline" "could not stage probes"; return 1; }
  since="$(fa_guest_now)"
  fa_agent net off >/dev/null 2>&1 \
    || fa_fatal "$vdir/probes-offline" "could not cut guest network"
  fa_run_probes "$vdir/probes-offline" probes-offline 0 "$cfg"
  fa_agent net on >/dev/null 2>&1 \
    || fa_fatal "$vdir/probes-offline" "could not restore guest network"
  fa_collect "$vdir/probes-offline" "$since"
  since="$(fa_guest_now)"
  fa_run_probes "$vdir/probes-online" probes-online 1 "$cfg"
  fa_collect "$vdir/probes-online" "$since"
}

# ── keybinds (feature-audit/11+) ─────────────────────────────────────────────

# fa_push_binds_lib — stage binds-guest.sh (the guest half of the keybind
# engine) where fa_gexec sources it.
fa_push_binds_lib() {
  fa_agent push "$INSTALLER_DIR/lib/feature-audit/binds-guest.sh" \
    /tmp/fa-binds >/dev/null 2>&1
}

# fa_gexec <fn> [args…] — run a binds-guest.sh function in the live session.
fa_gexec() {
  # vm-agent exec runs under set -e; the guest helpers branch on tests
  local cmd="set +e; source /tmp/fa-binds/binds-guest.sh;" a
  for a in "$@"; do cmd+=" $(printf '%q' "$a")"; done
  fa_agent exec "$cmd" 2>/dev/null
}

_fa_comp_proc() {
  case "$1" in niri) echo niri ;; hyprland) echo Hyprland ;;
    kde) echo kwin_wayland ;; esac
}

# _fa_send <chord | click:x,y> — one step of a bind's `pre`/`then` list.
_fa_send() {
  case "$1" in
    click:*)
      local xy="${1#click:}"
      fa_agent mouse move "${xy%,*}" "${xy#*,}" >/dev/null 2>&1
      fa_agent mouse btn left down >/dev/null 2>&1
      fa_agent mouse btn left up >/dev/null 2>&1 ;;
    *) fa_agent key "$1" >/dev/null 2>&1 ;;
  esac
}

# _fa_bind_recover <recovery> <chord> <desktop>
_fa_bind_recover() {
  case "$1" in
    escape)  fa_agent key Escape >/dev/null 2>&1 ;;
    toggle)  fa_agent key "$2" >/dev/null 2>&1 ;;
    key:*)   fa_agent key "${1#key:}" >/dev/null 2>&1 ;;
    unlock)  fa_agent unlock >/dev/null 2>&1 ;;
    session) fa_agent session "$3" >/dev/null 2>&1
             fa_agent idle off >/dev/null 2>&1
             fa_push_binds_lib
             fa_gexec fa_bbaseline >/dev/null ;;
  esac
  sleep 1
}

# _fa_mouse_chord <Mods+mouse_down|mouse_up|mouse:272|mouse:273> — hold the
# modifiers, then wheel (mouse_down/up) or drag from screen centre with the
# left (272) / right (273) button: real pointer input, like a hand would.
_fa_mouse_chord() {
  local chord="$1" mods btn
  mods="${chord%+mouse*}"; btn="${chord##*+}"
  [[ "$mods" == "$chord" ]] && mods=""
  fa_agent mouse move 16384 16384 >/dev/null 2>&1
  if [[ -n "$mods" ]]; then
    fa_agent keydown "$mods" >/dev/null 2>&1 || return 1
    sleep 0.3   # the compositor must see the modifier held first
  fi
  case "$btn" in
    mouse_down) fa_agent mouse wheel down ;;
    mouse_up)   fa_agent mouse wheel up ;;
    mouse:272|mouse:273)
      local b=left; [[ "$btn" == mouse:273 ]] && b=right
      fa_agent mouse move 16384 16384 && sleep 0.2 \
        && fa_agent mouse btn "$b" down && sleep 0.2 \
        && fa_agent mouse move 18000 17500 && sleep 0.2 \
        && fa_agent mouse move 20000 19000 && sleep 0.2 \
        && fa_agent mouse btn "$b" up ;;
    *) [[ -n "$mods" ]] && fa_agent keyup "$mods" >/dev/null 2>&1
       return 1 ;;
  esac >/dev/null 2>&1
  [[ -n "$mods" ]] && fa_agent keyup "$mods" >/dev/null 2>&1
  return 0
}

# _fa_bind_one <plan-row-json> <desktop> — one bind as real input; prints its
# PASS/FAIL/SKIP line.
_fa_bind_one() {
  local row="$1" de="$2" chord effect arg needs rec settle id b a t rc sdir
  chord="$(jq -r .chord <<<"$row")"; effect="$(jq -r .effect <<<"$row")"
  arg="$(jq -r '.arg // ""' <<<"$row")"
  needs="$(jq -r '.needs // ""' <<<"$row")"
  rec="$(jq -r '.recovery // ""' <<<"$row")"
  settle="$(jq -r '.settle // 1.5' <<<"$row")"
  id="bind-$(jq -r .source <<<"$row")-$chord"
  if [[ "$effect" == unverifiable ]]; then
    echo "SKIP $id unverifiable: $(jq -r '.reason // "no reason"' <<<"$row")"
    return
  fi
  sdir="Pictures/Screenshots"
  [[ "$effect" == file-created ]] && sdir="$arg"
  fa_gexec fa_bsetup "$needs" "$effect" "$arg" >/dev/null
  while IFS= read -r t; do
    [[ -n "$t" ]] && { _fa_send "$t"; sleep 1; }
  done < <(jq -r '.pre[]?' <<<"$row")
  b="$(fa_gexec fa_bstate "$sdir")"
  if [[ "$chord" == *mouse* ]]; then
    _fa_mouse_chord "$chord" \
      || { echo "SKIP $id mouse chord not injectable"; return; }
  elif ! fa_agent key "$chord" >/dev/null 2>&1; then
    echo "SKIP $id key not injectable by QEMU"; fa_gexec fa_bteardown; return
  fi
  while IFS= read -r t; do
    [[ -n "$t" ]] && { sleep 1; _fa_send "$t"; }
  done < <(jq -r '.then[]?' <<<"$row")
  if [[ "$effect" == session-ends ]]; then
    local p; p="$(_fa_comp_proc "$de")"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      fa_agent sudo "pgrep -x $p" >/dev/null 2>&1 || break
      sleep 1
    done
    if fa_agent sudo "pgrep -x $p" >/dev/null 2>&1; then
      echo "FAIL $id ($(jq -r .action <<<"$row")) did not end the session"
    else echo "PASS $id session ended"; fi
    _fa_bind_recover "${rec:-session}" "$chord" "$de"
    return
  fi
  sleep "$settle"
  a="$(fa_gexec fa_bstate "$sdir")"
  rc=0
  fa_gexec fa_beval "$effect" "$arg" "$b" "$a" >/dev/null || rc=$?
  case "$rc" in
    0) echo "PASS $id $effect" ;;
    3) echo "SKIP $id $effect not observable here (no audio device)" ;;
    *) echo "FAIL $id ($(jq -r .action <<<"$row")) expected" \
         "$effect${arg:+ $arg}, not observed" ;;
  esac
  [[ -n "$rec" ]] && _fa_bind_recover "$rec" "$chord" "$de"
  fa_gexec fa_bteardown >/dev/null
}

# fa_phase_keybinds <variant-dir> <cfg> — per compositor of the set, every
# shipped bind as real keyboard input; session-ending binds last.
fa_phase_keybinds() {
  local vdir="$1" cfg="$2" de src dir since out row first="" why
  first="$(fa_desktops "$cfg" | head -1)"
  while IFS= read -r de; do
    [[ -n "$de" ]] || continue
    dir="$vdir/keybinds-$de"; mkdir -p "$dir"
    since="$(fa_guest_now)"
    fa_agent session "$de" > "$dir/agent.txt" 2>&1 || {
      echo "keybinds: session $de not ready" >> "$dir/session-start.lines"
      continue; }
    fa_agent idle off >/dev/null 2>&1 || true
    fa_push_binds_lib
    fa_gexec fa_bbaseline >/dev/null
    for src in $(fa_binds_sources); do
      # app sources (session `*`) run once, in the first session
      case "$(fa_binds_session "$src")" in
        "$de") ;;  "*") [[ "$de" == "$first" ]] || continue ;;  *) continue ;;
      esac
      out="$dir/probe-binds-$src@$FA_USER.probe"
      # Probe Gate: binds this variant does not deploy are SKIPped, not judged
      if why="$(fa_bind_gate "$de" "$cfg")"; then
        fa_binds_plan "$src" | jq -r --arg w "$why" \
          'select(.effect != null) | "SKIP bind-\(.source)-\(.chord) \($w)"' \
          >> "$out"
        continue
      fi
      while IFS= read -r row; do
        _fa_bind_one "$row" "$de" >> "$out"
      done < <(fa_binds_plan "$src" | jq -c 'select(.effect != null)' \
                 | jq -s -c 'sort_by(.session_ending // false) | .[]')
    done
    fa_collect "$dir" "$since"
  done < <(fa_desktops "$cfg")
}

# ── Audit Cache (ADR 0152) ───────────────────────────────────────────────────
# The uncached base variant fills it (repo packages + its built AUR packages
# as the [audit-aur] repo); every later install of the run is pointed at it
# through the harness HTTP root. Base still exercises the real mirrors, AUR
# builds and AUR Vetting.

FA_CACHE_SOURCE=base   # the variant that installs uncached and fills it

fa_cache_dir() { printf '%s\n' "$CACHE_DIR/audit-cache"; }

# fa_cache_install_env <variant-id> — the test-only install env (K=V list).
fa_cache_install_env() {
  local c url
  c="$(fa_cache_dir)"
  url="http://$LIBVIRT_GATEWAY:$HTTP_PORT/audit-cache"
  if [[ "$1" == "$FA_CACHE_SOURCE" ]]; then
    echo INSTALL_PKG_CACHE_KEEP=1; return
  fi
  compgen -G "$c/pkg/*.pkg.tar.zst" >/dev/null || return 0
  printf '%s' "INSTALL_PKG_CACHE_SERVER=$url/pkg"
  [[ -e "$c/aur/audit-aur.db" ]] \
    && printf ' %s' "INSTALL_AUDIT_AUR_URL=$url/aur"
  echo
}

# fa_cache_harvest — after base's boot1: copy its kept repo packages and
# its built AUR packages to the host, index the AUR ones as [audit-aur], then
# clear the guest's pacman cache (the shipped state the install would leave).
# A failed copy drops the cache: the rest install uncached, never from a
# partial set.
fa_cache_harvest() {
  local c ok=1; c="$(fa_cache_dir)"
  mkdir -p "$c/pkg" "$c/aur"
  fa_agent sudo <<'SH' | tar -xf - -C "$c/pkg" || ok=0
tar -C /var/cache/pacman/pkg -cf - --wildcards '*.pkg.tar.zst'
SH
  ((PIPESTATUS[0] == 0)) || ok=0
  fa_agent sudo <<'SH' | tar -xf - -C "$c/aur" || ok=0
cd / && find home root -path '*/.cache/paru/clone/*' -name '*.pkg.tar.zst' \
  ! -name '*-debug-*' | tar -cf - -T - --transform 's|.*/||'
SH
  ((PIPESTATUS[0] == 0)) || ok=0
  if compgen -G "$c/aur/*.pkg.tar.zst" >/dev/null; then
    repo-add -q "$c/aur/audit-aur.db.tar.gz" "$c/aur"/*.pkg.tar.zst || ok=0
  fi
  if ((!ok)); then
    warn "Audit Cache harvest failed; later variants install uncached."
    rm -rf "$c"
  fi
  printf '%s\n' 'rm -f /var/cache/pacman/pkg/*.pkg.tar.zst' | fa_agent sudo \
    >/dev/null 2>&1 || true
}

# fa_install <variant-dir> <vm-profile-file> [<variant-id>] — install through
# the persistent flow (Audit Cache env per variant); 0 iff the installer
# exited 0.
fa_install() {
  local dir="$1/install" prof="$2" rc
  mkdir -p "$dir"
  VM_INSTALL_ENV="$(fa_cache_install_env "${3:-}")" \
    VM_ARTIFACT_DIR="$dir" VM_HOLD_FOR_LOG_PULL=1 VM_SKIP_FINAL_BOOT=1 \
    VM_PM=1 \
    REPO_URL="$FA_REPO_URL" \
    bash "$INSTALLER_DIR/vm/vm.sh" --profile "$prof" --recreate \
    > "$dir/harness.txt" 2>&1 || true
  rc="$(cat "$dir/install-rc" 2>/dev/null || echo none)"
  case "$rc" in
    0) return 0 ;;
    none) fa_fatal "$dir" \
            "installer never reported an exit (see harness.txt)" ;;
    124) fa_fatal "$dir" "installer timed out" ;;
    *) fa_fatal "$dir" "installer exited $rc" ;;
  esac
  return 1
}

fa_destroy_vm() {
  fa_serial_stop
  VM_NAME="$VM_NAME" _vm_destroy_undefine >/dev/null 2>&1 || true
}

# fa_run_guided <variant-dir> <profile-ref> — the menu-driven path runs the
# disposable guided test flow (install + boot-verify), not the persistent one:
# the guest assembles its config from replayed menu answers. Only the install
# and boot phases apply; it is not agent-controllable.
fa_run_guided() {
  local dir="$1" ref="$2" gname rc=0
  gname="$(jsonc_strip "$INSTALLER_DIR/tests/vm/profiles/$ref.jsonc" \
    | jq -r .name)"
  mkdir -p "$dir/install" "$dir/boot1"
  LOG_FILE="$dir/install/installer.log" \
    BOOT_LOG_FILE="$dir/boot1/serial.log" REPO_URL="$FA_REPO_URL" \
    CACHE_DIR="$CACHE_DIR" VM_INSTALL_ENV="$(fa_cache_install_env guided)" \
    bash "$INSTALLER_DIR/vm/vm.sh" --guided --profile "$ref" --verify-boot \
    --recreate > "$dir/install/harness.txt" 2>&1 || rc=$?
  ((rc == 0)) || fa_fatal "$dir/install" \
    "guided install or boot-verify failed (vm.sh exit $rc; see harness.txt)"
  VM_NAME="$gname" _vm_destroy_undefine >/dev/null 2>&1 || true
}

# fa_phase_wanted <variant-dir> <phase> — run this phase? FEATURE_AUDIT_SKIP
# (space list) drops phases silently, for a quick partial run while
# iterating; a phase outside the variant's Variant Phases is recorded as a
# SKIP (never passed, never silent).
fa_phase_wanted() {
  local dir="$1" p="$2"
  [[ " ${FEATURE_AUDIT_SKIP:-} " != *" $p "* ]] || return 1
  [[ -z "${FA_VARIANT_PHASES:-}" \
     || " $FA_VARIANT_PHASES " == *" $p "* ]] && return 0
  mkdir -p "$dir/$p"
  echo "SKIP phase-$p not in this variant's Variant Phases" \
    > "$dir/$p/phase@gate.probe"
  return 1
}

# fa_run_variant <id> <run-dir> — every phase for one variant.
fa_run_variant() {
  local id="$1" run="$2" dir prof cfg v
  dir="$run/$id"
  mkdir -p "$dir"
  section "Audit Variant: $id"
  v="$(fa_variant_json "$id")"
  jq --arg sha "$(git -C "$INSTALLER_DIR" rev-parse HEAD)" \
    --arg at "$(date -Is)" \
    '{variant: .id, adrs: (.adrs // []), commit: $sha, started: $at}' \
    <<<"$v" > "$dir/variant.json"
  local guided
  guided="$(jq -r '.guided // empty' <<<"$v")"
  if [[ -n "$guided" ]]; then fa_run_guided "$dir" "$guided"; return; fi
  prof="$dir/vm-profile.json"
  fa_variant_vm_profile "$id" > "$prof" \
    || { fa_fatal "$dir/install" "variant does not resolve"; return 1; }
  cfg="$(fa_variant_config "$id")" || cfg='{}'
  # the Host Core gate the probes read (fa_host_core)
  cfg="$(jq -c --argjson hc "$(fa_variant_host_core "$id" || echo true)" \
    '. + {_audit: {host_core: $hc}}' <<<"$cfg")"
  FA_USER="$(jq -r '.users[0] // "aquastias"' <<<"$cfg")"
  FA_VARIANT_PHASES="$(fa_variant_phases "$id")"
  VM_RAM_MB="$(jq -r '.hardware.ram_mb' "$prof")"   # capacity preflight
  export VM_RAM_MB

  if [[ -n "${FA_REUSE:-}" ]]; then
    # --reuse: audit the already-installed VM as it stands (iterate on the
    # later phases or re-check a fix without a reinstall)
    mkdir -p "$dir/boot1"
    _vm_running || fa_vm_start "$dir/boot1" || return 1
    fa_serial_start "$dir/boot1/serial.log"
    fa_wait_ssh "$FA_BOOT_TIMEOUT_SEC" \
      || { fa_fatal "$dir/boot1" "reused VM never reached SSH"; return 1; }
  else
    fa_install "$dir" "$prof" "$id" || return 1
    fa_boot "$dir/boot1" || return 1
    [[ "$id" == "$FA_CACHE_SOURCE" ]] && fa_cache_harvest
  fi
  fa_collect "$dir/boot1"
  fa_phase_wanted "$dir" sessions && fa_phase_sessions "$dir" "$cfg"
  fa_phase_wanted "$dir" probes && fa_phase_probes "$dir" "$cfg"
  fa_phase_wanted "$dir" keybinds && fa_phase_keybinds "$dir" "$cfg"
  fa_phase_wanted "$dir" timers && fa_phase_timers "$dir"
  if fa_phase_wanted "$dir" boot2; then
    fa_phase_boot2 "$dir" "$cfg" || return 1
  fi
  if fa_phase_wanted "$dir" upgrade; then
    fa_phase_upgrade "$dir" || return 1
  fi
  # last: a QEMU virtio-gpu guest can come back from S3 with its compositor
  # / seatd wedged, which would hang every later reboot (base, 20261002)
  fa_phase_wanted "$dir" power && fa_phase_power "$dir"
  fa_serial_stop
}

# fa_run [--variant X] [--from X] [--keep] [--reuse] — the Audit Run.
fa_run() {
  local only="" from="" keep=0
  while (($#)); do
    case "$1" in
      --variant) only="${2:?}"; shift 2 ;;
      --from)    from="${2:?}"; shift 2 ;;
      --keep)    keep=1; shift ;;
      --reuse)   FA_REUSE=1; keep=1; shift ;;
      *) echo "feature-audit: unknown run option '$1'" >&2; return 2 ;;
    esac
  done
  _ensure_libvirt_reachable
  VM_NAME="$(fa_manifest_json | jq -r .vm_name)"
  export VM_NAME
  local -a ids=() all
  mapfile -t all < <(fa_variant_ids)
  local id started=0
  for id in "${all[@]}"; do
    if [[ -n "$only" ]]; then [[ "$id" == "$only" ]] && ids+=("$id")
    elif [[ -n "$from" ]]; then
      [[ "$id" == "$from" ]] && started=1
      ((started)) && ids+=("$id")
    else ids+=("$id"); fi
  done
  ((${#ids[@]})) || { echo "feature-audit: no variant selected" >&2; return 2; }

  local run; run="$(fa_runs_root)/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$run"
  info "Audit Run → $run"
  mkdir -p "$run/audit/check"
  fa_audit_check > "$run/audit/check/check.lines" \
    || warn "check found problems (recorded as Findings); running anyway."
  [[ -n "${FA_REUSE:-}" && ${#ids[@]} -ne 1 ]] \
    && { echo "feature-audit: --reuse needs one --variant" >&2; return 2; }
  [[ -n "${FA_REUSE:-}" ]] || FA_REPO_URL="$(fa_stage_repo)"
  local i n=${#ids[@]}
  # the Audit Cache is per run: never reused from an earlier one
  [[ -n "${FA_REUSE:-}" ]] || rm -rf "$(fa_cache_dir)"
  for ((i = 0; i < n; i++)); do
    fa_run_variant "${ids[i]}" "$run" || true
    fa_report "$run" >/dev/null || true   # findings so far, per variant
    fa_serial_stop
    if ((keep && i == n - 1)); then
      info "Keeping VM '$VM_NAME' for inspection (--keep)."
    else
      fa_destroy_vm
    fi
  done
  fa_report "$run"
}
