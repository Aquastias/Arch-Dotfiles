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
#
# Used by: tools/feature-audit.sh (run).
# =============================================================================

# shellcheck source=../../vm/lib/core.sh
[[ "$(type -t _core_vm_running)" == function ]] \
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

feature_audit_runs_root() {
  printf '%s\n' "${FEATURE_AUDIT_RUNS:-$INSTALLER_DIR/.audit-runs}"
}

# feature_audit_agent <verb> [args…] — VM Agent Control on the audit VM as its
# user. stdin reaches the guest only for a stdin-script `sudo`; every other call
# gets /dev/null, or ssh would swallow the caller's `while read` input.
feature_audit_agent() {
  if [[ "$1" == sudo && $# -eq 1 ]]; then
    bash "$FA_AGENT" --vm "$VM_NAME" --user "$FA_USER" "$@"
  else
    bash "$FA_AGENT" --vm "$VM_NAME" --user "$FA_USER" "$@" </dev/null
  fi
}

# feature_audit_fatal <phase-dir> <message> — record a fatal Finding for this
# phase.
feature_audit_fatal() {
  mkdir -p "$1"
  printf '%s\n' "$2" >> "$1/fatal.lines"
  warn "FATAL: $2"
}

# feature_audit_stage_repo — serve the committed HEAD to the guest, so the
# audit tests local commits without a push (vm/lib/repo-source.sh).
feature_audit_stage_repo() {
  vm_repo_source_stage_local "$CACHE_DIR" feature-audit-repo.git
}

# feature_audit_wait_ssh <timeout> — until the guest's sshd answers for the
# audit user.
feature_audit_wait_ssh() {
  local timeout="$1" elapsed=0 ip
  while ((elapsed < timeout)); do
    ip="$(_core_vm_ip_now)"
    if [[ -n "$ip" ]] && feature_audit_agent sudo true >/dev/null 2>&1; then
      return 0
    fi
    sleep 5; elapsed=$((elapsed + 5))
  done
  return 1
}

# feature_audit_serial_start <log> — capture serial + answer disk-unlock prompts
# for the whole time the domain runs (survives guest reboots).
feature_audit_serial_start() {
  local log="$1" dev
  _core_start_console_capture "$log" >/dev/null
  dev="$(virsh ttyconsole "$VM_NAME" 2>/dev/null)" || dev=""
  if [[ -n "$dev" ]]; then
    vm_console_answerer_watch "$log" "$dev" &
    FA_ANSWER_PID=$!
  fi
}

feature_audit_serial_stop() {
  _core_stop_console_capture
  [[ -n "$FA_ANSWER_PID" ]] || return 0
  kill "$FA_ANSWER_PID" 2>/dev/null || true
  wait "$FA_ANSWER_PID" 2>/dev/null || true
  FA_ANSWER_PID=""
}

# feature_audit_vm_start <phase-dir> — power the domain on behind the
# host-capacity guard (ADR 0099); a refusal is this variant's fatal, not the
# run's.
feature_audit_vm_start() {
  if ! ( _core_vm_capacity_preflight ) >/dev/null 2>&1; then
    feature_audit_fatal "$1" "host capacity: ${VM_RAM_MB:-?} MiB VM refused"
    return 1
  fi
  mkdir -p "$1"
  # "already running" is fine; any error is kept as boot-fatal evidence.
  virsh start "$VM_NAME" >/dev/null 2>"$1/virsh-start.err" || true
  [[ -s "$1/virsh-start.err" ]] || rm -f "$1/virsh-start.err"
}

# feature_audit_boot_evidence <phase-dir> — on a boot fatal, keep what the host
# still sees: the domain state and the VGA console (the serial log can be
# empty).
feature_audit_boot_evidence() {
  mkdir -p "$1"
  virsh domstate --reason "$VM_NAME" > "$1/domstate.txt" 2>&1 || true
  virsh screenshot "$VM_NAME" "$1/console.png" >/dev/null 2>&1 || true
}

# feature_audit_wait_until <cap-sec> <guest-check> — poll a root shell check on
# the guest every 5s; return once it holds twice in a row, or at the cap. The
# readiness form of a fixed settle: a quiet guest is judged at once, a busy one
# still gets the old full wait.
feature_audit_wait_until() {
  local timeout="$1" check="$2" ok=0 end
  end=$((SECONDS + timeout))
  # wall clock, not the sleeps: a slow guest check counts toward the cap
  while ((SECONDS < end)); do
    if feature_audit_agent sudo <<<"$check" >/dev/null 2>&1; then
      ok=$((ok + 1)); ((ok >= 2)) && return 0
    else ok=0; fi
    sleep 5
  done
}

# Settled: no systemd job queued and the boot has left `starting`.
# shellcheck disable=SC2016 # a guest shell command, expanded in the guest
_FA_SETTLED='[ -z "$(systemctl list-jobs --no-legend)" ] &&
  ! systemctl is-system-running 2>/dev/null | grep -qxE "starting|initializing"'
# …and no unit still activating (the timer soak's delayed work).
# shellcheck disable=SC2016 # a guest shell command, expanded in the guest
_FA_NONE_ACTIVATING='[ -z "$(systemctl list-units --state=activating \
  --no-legend)" ]'

# _live_settled — the settle check: the system is settled and, with linger,
# so is the audit user's manager (a first container pull runs there).
_live_settled() {
  printf '%s' "$_FA_SETTLED"
  if [[ -n "${FA_USER:-}" ]]; then
    # shellcheck disable=SC2016 # a guest shell command, expanded in the guest
    printf ' && [ -z "$(systemctl --user -M %s@ list-jobs --no-legend %s)" ]' \
      "$FA_USER" '2>/dev/null'
  fi
}

# feature_audit_boot <phase-dir> — power on the installed system and wait for
# SSH.
feature_audit_boot() {
  local directory="$1" up=1
  mkdir -p "$directory"
  feature_audit_vm_start "$directory" || return 1
  feature_audit_serial_start "$directory/serial.log"
  feature_audit_wait_ssh "$FA_BOOT_TIMEOUT_SEC" || up=0
  if ((!up)) && _live_boot_silent "$directory"; then
    # not even firmware output: a domain-start glitch, not the install —
    # power-cycle once (base + niri-pure, 20261003)
    echo "silent boot (no serial output); power-cycled once" \
      >> "$directory/vm-retry.txt"
    feature_audit_serial_stop
    virsh destroy "$VM_NAME" >/dev/null 2>&1 || true
    feature_audit_vm_start "$directory" || return 1
    feature_audit_serial_start "$directory/serial.log"
    up=1; feature_audit_wait_ssh "$FA_BOOT_TIMEOUT_SEC" || up=0
  fi
  ((up)) || { _live_boot_fatal "$directory"; return 1; }
  feature_audit_wait_until "$FA_SETTLE_SEC" "$(_live_settled)"
}

# _live_boot_silent <phase-dir> — the serial capture holds no guest output.
_live_boot_silent() {
  ! grep -q -v -e '^Script ' -e '^Connected to domain' -e '^Escape character' \
    -e '^\s*$' "$1/serial.log" 2>/dev/null
}

_live_boot_fatal() {
  feature_audit_boot_evidence "$1"
  feature_audit_fatal "$1" \
    "installed system never reached SSH (${FA_BOOT_TIMEOUT_SEC}s)"
  return 1
}

_FA_BOOT_ID=/proc/sys/kernel/random/boot_id

# feature_audit_await_new_boot <phase-dir> <old-boot-id> — wait for the guest to
# come back as a new boot. The VM's virgl GPU can stall, leaving GPU clients in
# D state so shutdown never ends (a host artefact, not the product): after the
# grace, hard-reset the domain and record it in vm-reset.txt.
feature_audit_await_new_boot() {
  local directory="$1" old="$2" id elapsed=0 down=0
  _FA_DID_RESET=0
  while ((elapsed < ${FA_SHUTDOWN_GRACE_SEC:-240})); do
    sleep 10; elapsed=$((elapsed + 10))
    id="$(feature_audit_agent sudo cat "$_FA_BOOT_ID" 2>/dev/null)" \
      || { id=""; down=1; }
    # an unknown old id: trust an id only once the guest has been down
    if [[ -n "$id" && "$id" != "$old" ]] && { [[ -n "$old" ]] || ((down)); }
    then return 0; fi
  done
  virsh reset "$VM_NAME" >/dev/null 2>&1 || true
  _FA_DID_RESET=1
  mkdir -p "$directory"
  printf 'reboot wedged in shutdown for %ss (virgl GPU stall); reset\n' \
    "${FA_SHUTDOWN_GRACE_SEC:-240}" >> "$directory/vm-reset.txt"
}

# feature_audit_reboot <phase-dir> — guest reboot, wait for SSH, settle. The
# serial capture + answerer keep running across the reboot.
feature_audit_reboot() {
  local directory="$1" old
  mkdir -p "$directory"
  old="$(feature_audit_agent sudo cat "$_FA_BOOT_ID" 2>/dev/null)" || old=""
  feature_audit_agent sudo systemctl reboot >/dev/null 2>&1 || true
  feature_audit_await_new_boot "$directory" "$old"
  feature_audit_wait_ssh "$FA_BOOT_TIMEOUT_SEC" || {
    feature_audit_boot_evidence "$directory"
    feature_audit_fatal "$directory" \
      "no SSH after reboot (${FA_BOOT_TIMEOUT_SEC}s)"
    return 1
  }
  # the wedged boot's last words, for the cause of a stall
  ((_FA_DID_RESET)) && feature_audit_agent sudo \
    "journalctl -b -1 -n 300 --no-pager" \
    > "$directory/prev-boot-journal.txt" 2>&1
  feature_audit_wait_until "$FA_SETTLE_SEC" "$(_live_settled)"
}

# _FA_FOLD_HUNG_TASKS — awk: join a kernel hung-task report (header … </TASK>)
# into one journal line, so Known Noise can judge it whole by its stack (a
# virgl stall vs a real hang); every other line passes through.
# shellcheck disable=SC2016 # an awk program, not shell
_FA_FOLD_HUNG_TASKS='
  / kernel: INFO: task .* blocked for more than / {
    if (on) print b
    b = $0; on = 1; next
  }
  on && / kernel: / {
    l = $0; sub(/^.* kernel: +/, "", l); b = b " | " l
    if (l ~ /^<\/TASK>/) { print b; on = 0 }
    next
  }
  on { print b; on = 0 }
  { print }
  END { if (on) print b }'

# _live_collect_script [since-epoch] — guest-side (root) signal collector.
# With a since-epoch only that window's journal/coredumps are taken, so an
# in-boot phase reports its own lines, not the whole boot's again.
_live_collect_script() {
  printf 'SINCE=%q\n' "${1:-}"
  printf 'FOLD=%q\n' "$_FA_FOLD_HUNG_TASKS"
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
journalctl "${win[@]}" --system -p warning --no-pager -q -o short 2>&1 \
  | awk "$FOLD" > "$o/journal.lines"
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

# feature_audit_guest_now — the guest's epoch (phase windows are guest-clock
# based).
feature_audit_guest_now() {
  feature_audit_agent sudo date +%s 2>/dev/null \
    | awk '{ gsub(/[^0-9]/, ""); printf "%s", $0 }'
}

# feature_audit_pull_into <guest-dir> <host-dir> — pull a guest dir's files
# flat.
feature_audit_pull_into() {
  local staging_directory; staging_directory="$(mktemp -d)"
  if feature_audit_agent pull "$1" "$staging_directory" >/dev/null 2>&1; then
    mkdir -p "$2"
    cp -rf "$staging_directory/${1##*/}/." "$2/" 2>/dev/null || true
    rm -rf "$staging_directory"; return 0
  fi
  rm -rf "$staging_directory"; return 1
}

# feature_audit_collect <phase-dir> [since-epoch] — harvest signals for the
# phase.
feature_audit_collect() {
  local directory="$1" error_file="$1/collector-err.txt"
  mkdir -p "$directory"
  # one retry once SSH answers: a lone failure right after boot (refind
  # 20261007) is not the guest's fault; stderr kept as the evidence
  if ! _live_collect_script "${2:-}" \
    | feature_audit_agent sudo >/dev/null 2>"$error_file"; then
    feature_audit_wait_ssh 120 || true
    _live_collect_script "${2:-}" \
      | feature_audit_agent sudo >/dev/null 2>>"$error_file" || {
      feature_audit_fatal "$directory" "collector failed to run in the guest:\
 $(awk 'END { print }' "$error_file")"
      return 1
    }
  fi
  [[ -s "$error_file" ]] || rm -f "$error_file"
  feature_audit_pull_into /tmp/fa-collect "$directory" \
    || feature_audit_fatal "$directory" "could not pull collected artifacts"
}


# The Audit Run's parts.
# shellcheck source=./live-phases.sh
source "${BASH_SOURCE[0]%/*}/live-phases.sh"
# shellcheck source=./live-probes.sh
source "${BASH_SOURCE[0]%/*}/live-probes.sh"
# shellcheck source=./live-keybinds.sh
source "${BASH_SOURCE[0]%/*}/live-keybinds.sh"
# shellcheck source=./live-run.sh
source "${BASH_SOURCE[0]%/*}/live-run.sh"
