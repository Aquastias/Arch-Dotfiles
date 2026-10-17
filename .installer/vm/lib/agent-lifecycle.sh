#!/usr/bin/env bash
# =============================================================================
# vm/lib/agent-lifecycle.sh — VM Agent Control power verbs (ADR 0117, 0155)
# =============================================================================
# status / start / stop for the selected VM, so an agent never hand-rolls
# `virsh list|start|destroy`. Unlike the session verbs these work on a VM that
# is shut off. `start` keeps the one-VM-at-a-time rule (ADR 0155).
#
# Public API:
#   agent_lifecycle_status   → "<vm>: <state> [ip=<ip>]" + other running VMs
#   agent_lifecycle_start    → start the VM unless another VM is running
#   agent_lifecycle_stop     → ACPI shutdown; force off past the grace period
#
# Used by: vm/vm-agent.sh (sources it; supplies VM_NAME, _vm_ip, die, info and
# AGENT_SHUTDOWN_GRACE).
# =============================================================================

# shellcheck source=./host-capacity.sh
declare -F vm_host_capacity_others_running >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/host-capacity.sh"

# _agent_lifecycle_state — the domain state (`running`, `shut off`, …), or
# `undefined` when libvirt has no such domain.
_agent_lifecycle_state() {
  local state
  state="$(virsh domstate "$VM_NAME" 2>/dev/null)" || state=undefined
  printf '%s\n' "${state%%$'\n'*}"
}

# _agent_lifecycle_others — running domains other than VM_NAME, one per line.
_agent_lifecycle_others() {
  local running
  mapfile -t running < <(virsh list --name --state-running 2>/dev/null)
  vm_host_capacity_others_running "$VM_NAME" "${running[@]}"
}

agent_lifecycle_status() {
  local state ip others
  state="$(_agent_lifecycle_state)"
  if [[ "$state" == running ]]; then
    ip="$(_vm_ip)"
    printf '%s: running ip=%s\n' "$VM_NAME" "${ip:-none}"
  else
    printf '%s: %s\n' "$VM_NAME" "$state"
  fi
  others="$(_agent_lifecycle_others)"
  [[ -z "$others" ]] || printf 'other running: %s\n' "${others//$'\n'/, }"
}

agent_lifecycle_start() {
  local state others
  state="$(_agent_lifecycle_state)"
  [[ "$state" != undefined ]] \
    || die "VM '$VM_NAME' is not defined — create it with vm.sh --profile …"
  [[ "$state" != running ]] || { info "'$VM_NAME' already running."; return; }
  others="$(_agent_lifecycle_others)"
  [[ -z "$others" || "${VM_ALLOW_PARALLEL:-false}" == true ]] \
    || die "other VM(s) running: ${others//$'\n'/, } — stop them first" \
      "(one VM at a time, ADR 0155) or set VM_ALLOW_PARALLEL=true"
  virsh start "$VM_NAME" >/dev/null || die "virsh start '$VM_NAME' failed"
  info "started '$VM_NAME' — \`ready\` waits for its session."
}

agent_lifecycle_stop() {
  local elapsed=0
  [[ "$(_agent_lifecycle_state)" == running ]] \
    || { info "'$VM_NAME' is not running."; return 0; }
  info "shutting down '$VM_NAME' (≤${AGENT_SHUTDOWN_GRACE}s, then force)…"
  virsh shutdown "$VM_NAME" >/dev/null 2>&1 || true
  while ((elapsed < AGENT_SHUTDOWN_GRACE)); do
    [[ "$(_agent_lifecycle_state)" == running ]] || {
      info "'$VM_NAME' shut off."
      return 0
    }
    sleep 5; elapsed=$((elapsed + 5))
  done
  info "shutdown wedged ${elapsed}s — forcing off."
  virsh destroy "$VM_NAME" >/dev/null || die "virsh destroy '$VM_NAME' failed"
}
