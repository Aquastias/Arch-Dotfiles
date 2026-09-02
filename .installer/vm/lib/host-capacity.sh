#!/usr/bin/env bash
# =============================================================================
# vm/lib/host-capacity.sh — host-safety capacity decisions (ADR 0099)
# =============================================================================
# Pure fact-in / decision-out cores that keep the harness from crashing the host
# by over-committing RAM (the standing "never run so many VMs that you crash the
# host" rule). The IO shell probes the facts (MemTotal, nproc) and feeds them
# here; no probing, no TTY, no VM — so the policy is unit-testable.
#
# The Combination Matrix has its OWN parallel guard (lib/matrix/guard.sh, ADR
# 0046) for its concurrent scheduler and is not duplicated here. This module is
# the general guard for a DIRECT `vm.sh` launch — which never touches the matrix
# guard — plus the cores-aware cap + force-serial primitives an orchestrator can
# reuse.
#
# Public API:
#   host_capacity_max_vms <free_mb> <cores> [per_vm_mb] [cap]
#       → concurrent-VM cap: min(free/per_vm, cores), clamped to [1, cap]
#   host_capacity_force_serial <graphical> <persistent> <desktop_verify>
#       → exit 0 when any heavy axis is set (such VMs must never stack)
#   host_capacity_admit <vm_ram_mb> <host_total_mb> [safe_pct]
#       → exit 0 iff one VM of that size stays within safe_pct% of host RAM
# =============================================================================

# Defaults (env overrides win).
: "${HOST_CAP_PER_VM_MB:=4096}"    # RAM budget assumed per VM
: "${HOST_CAP_DEFAULT_MAX:=2}"     # conservative hard cap on concurrent VMs
: "${HOST_CAP_SAFE_PCT:=80}"       # a single VM may use ≤ this % of host RAM

# host_capacity_max_vms <free_mb> <cores> [per_vm_mb] [cap]
# The concurrency cap from BOTH constraints: RAM-fit (free / per_vm) and cores
# (one VM per core is already generous), whichever is smaller, clamped to
# [1, cap]. Never below 1 — whether even one VM fits is host_capacity_admit's
# call, not this one's.
host_capacity_max_vms() {
  local free_mb="$1" cores="$2"
  local per_vm="${3:-$HOST_CAP_PER_VM_MB}" cap="${4:-$HOST_CAP_DEFAULT_MAX}"
  (( per_vm > 0 )) || per_vm="$HOST_CAP_PER_VM_MB"
  local ram_fit=$(( free_mb / per_vm ))
  local fit=$(( ram_fit < cores ? ram_fit : cores ))
  (( fit > cap )) && fit="$cap"
  (( fit < 1 ))   && fit=1
  printf '%s\n' "$fit"
}

# host_capacity_force_serial <graphical> <persistent> <desktop_verify>
# Heavy VMs — a real graphical session, a persistent desktop VM, or a
# desktop-verify run — must never stack (GPU/CPU contention on top of RAM), so
# any of them forces the effective concurrency to serial. Exit 0 = force serial.
host_capacity_force_serial() {
  [[ "${1:-}" == true || "${2:-}" == true || "${3:-}" == true ]]
}

# host_capacity_admit <vm_ram_mb> <host_total_mb> [safe_pct]
# The single-VM launch gate: exit 0 iff this VM's RAM is within safe_pct% of
# total host RAM, so even one VM never thrashes the host. Reject (1) otherwise,
# or when host_total is unknown/zero.
host_capacity_admit() {
  local vm_mb="$1" host_mb="$2" pct="${3:-$HOST_CAP_SAFE_PCT}"
  [[ "$vm_mb" =~ ^[0-9]+$ && "$host_mb" =~ ^[0-9]+$ ]] || return 1
  (( host_mb > 0 )) || return 1
  (( vm_mb * 100 <= host_mb * pct ))
}
