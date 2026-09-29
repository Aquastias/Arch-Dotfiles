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

fa_runs_root() { printf '%s\n' "${FEATURE_AUDIT_RUNS:-$INSTALLER_DIR/.audit-runs}"; }

# fa_agent <verb> [args…] — VM Agent Control on the audit VM as its user.
fa_agent() {
  bash "$FA_AGENT" --vm "$VM_NAME" --user "$FA_USER" "$@"
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
    || warn "Uncommitted changes are NOT audited (the guest clones HEAD)."
  rm -rf "$dst"
  git clone -q --bare "$top" "$dst"
  git -C "$dst" repack -a -d -q
  git -C "$dst" update-server-info
  printf 'http://%s:%s/feature-audit-repo.git\n' "$LIBVIRT_GATEWAY" \
    "$HTTP_PORT"
}

_fa_vm_ip() {
  virsh domifaddr "$VM_NAME" 2>/dev/null \
    | awk 'NR>2 { split($4,a,"/"); if (a[1] ~ /^[0-9]/) print a[1] }' | head -1
}

# fa_wait_ssh <timeout> — until the guest's sshd answers for the audit user.
fa_wait_ssh() {
  local t="$1" e=0 ip
  while ((e < t)); do
    ip="$(_fa_vm_ip)"
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

# fa_boot <phase-dir> — power on the installed system and wait for SSH.
fa_boot() {
  local dir="$1"
  mkdir -p "$dir"
  virsh start "$VM_NAME" >/dev/null 2>&1 || true
  fa_serial_start "$dir/serial.txt"
  fa_wait_ssh "$FA_BOOT_TIMEOUT_SEC" || {
    fa_fatal "$dir" "installed system never reached SSH (${FA_BOOT_TIMEOUT_SEC}s)"
    return 1
  }
  sleep "$FA_SETTLE_SEC"
}

# fa_reboot <phase-dir> — guest reboot, wait for SSH, settle. The serial
# capture + answerer keep running across the reboot.
fa_reboot() {
  local dir="$1"
  mkdir -p "$dir"
  fa_agent sudo systemctl reboot >/dev/null 2>&1 || true
  sleep 15
  fa_wait_ssh "$FA_BOOT_TIMEOUT_SEC" || {
    fa_fatal "$dir" "no SSH after reboot (${FA_BOOT_TIMEOUT_SEC}s)"
    return 1
  }
  sleep "$FA_SETTLE_SEC"
}

# _fa_collect_script — guest-side (root) signal collector for the current
# boot. Writes report-ready artifacts into /tmp/fa-collect.
_fa_collect_script() {
  cat <<'SH'
set -u
o=/tmp/fa-collect
rm -rf "$o"; mkdir -p "$o"
systemctl --failed --plain --no-legend --no-pager \
  > "$o/failed-units-system.lines" 2>&1
for u in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $2}'); do
  systemctl --user -M "$u@" --failed --plain --no-legend --no-pager \
    > "$o/failed-units-user-$u.lines" 2>/dev/null || true
done
journalctl -b -p warning --no-pager -q -o short > "$o/journal.lines" 2>&1
coredumpctl list --no-legend --no-pager -q > "$o/coredumps.lines" 2>/dev/null \
  || true
chmod -R a+rX "$o"
SH
}

# fa_collect <phase-dir> — harvest the current boot's signals.
fa_collect() {
  local dir="$1" tmp
  mkdir -p "$dir"
  _fa_collect_script | fa_agent sudo >/dev/null 2>&1 \
    || { fa_fatal "$dir" "collector failed to run in the guest"; return 1; }
  tmp="$(mktemp -d)"
  if fa_agent pull /tmp/fa-collect "$tmp" >/dev/null 2>&1; then
    cp -f "$tmp"/fa-collect/* "$dir"/ 2>/dev/null || true
  else
    fa_fatal "$dir" "could not pull collected artifacts"
  fi
  rm -rf "$tmp"
}

# fa_install <variant-dir> <vm-profile-file> — install through the persistent
# flow; 0 iff the installer exited 0.
fa_install() {
  local dir="$1/install" prof="$2" rc
  mkdir -p "$dir"
  VM_ARTIFACT_DIR="$dir" VM_HOLD_FOR_LOG_PULL=1 VM_SKIP_FINAL_BOOT=1 \
    REPO_URL="$FA_REPO_URL" \
    bash "$INSTALLER_DIR/vm/vm.sh" --profile "$prof" --recreate \
    > "$dir/harness.txt" 2>&1 || true
  rc="$(cat "$dir/install-rc" 2>/dev/null || echo none)"
  case "$rc" in
    0) return 0 ;;
    none) fa_fatal "$dir" "installer never reported an exit (see harness.txt)" ;;
    124) fa_fatal "$dir" "installer timed out" ;;
    *) fa_fatal "$dir" "installer exited $rc" ;;
  esac
  return 1
}

fa_destroy_vm() {
  fa_serial_stop
  VM_NAME="$VM_NAME" _vm_destroy_undefine >/dev/null 2>&1 || true
}

# fa_run_variant <id> <run-dir> — every phase for one variant.
fa_run_variant() {
  local id="$1" run="$2" dir prof cfg
  dir="$run/$id"
  mkdir -p "$dir"
  section "Audit Variant: $id"
  prof="$dir/vm-profile.json"
  fa_variant_vm_profile "$id" > "$prof" \
    || { fa_fatal "$dir/install" "variant does not resolve"; return 1; }
  cfg="$(fa_variant_config "$id")" || cfg='{}'
  FA_USER="$(jq -r '.users[0] // "aquastias"' <<<"$cfg")"
  jq -n --arg id "$id" --arg sha "$(git -C "$INSTALLER_DIR" rev-parse HEAD)" \
    --arg at "$(date -Is)" '{variant:$id, commit:$sha, started:$at}' \
    > "$dir/variant.json"

  fa_install "$dir" "$prof" || return 1
  fa_boot "$dir/boot1" || return 1
  fa_collect "$dir/boot1"
  fa_serial_stop
}

# fa_run [--variant X] [--from X] [--keep] — the Audit Run.
fa_run() {
  local only="" from="" keep=0
  while (($#)); do
    case "$1" in
      --variant) only="${2:?}"; shift 2 ;;
      --from)    from="${2:?}"; shift 2 ;;
      --keep)    keep=1; shift ;;
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
  FA_REPO_URL="$(fa_stage_repo)"
  local i n=${#ids[@]}
  for ((i = 0; i < n; i++)); do
    fa_run_variant "${ids[i]}" "$run" || true
    fa_serial_stop
    if ((keep && i == n - 1)); then
      info "Keeping VM '$VM_NAME' for inspection (--keep)."
    else
      fa_destroy_vm
    fi
  done
  fa_report "$run"
}
