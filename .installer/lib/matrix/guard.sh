#!/usr/bin/env bash
# =============================================================================
# lib/matrix/guard.sh — Combination Matrix host-resource guard (ADR 0046)
# =============================================================================
# Pure decision cores that keep `matrix.sh run` from freezing the host. The IO
# shell probes the facts (MemAvailable, /dev/kvm, libvirtd, free disk) and feeds
# them here; every function is a pure fact-in / decision-out predicate — no
# probing, no TTY, no VM — so the scheduling policy is unit-testable.
#
# Public API:
#   matrix_guard_max_parallel <avail_kib> <reserve_kib> <per_vm_kib> <cap>
#       → VMs that fit: floor((avail − reserve) / per_vm), clamped to [0,cap]
#   matrix_guard_preflight_reason <has_kvm> <libvirtd_up> <free> <need>
#       → "" when the host can run VMs; else a one-line structured reason
#   matrix_guard_can_launch <free_mem_kib> <reserve_kib> <per_vm_kib>
#       → exit 0 when one more VM fits now; the per-spawn gate predicate
# =============================================================================

# matrix_guard_max_parallel <avail_kib> <reserve_kib> <per_vm_kib> <cap>
# The count of VMs that fit in the host's free RAM after the reserve, never
# more than the cap.
matrix_guard_max_parallel() {
  local avail="$1" reserve="$2" per_vm="$3" cap="$4" fit
  fit=$(( (avail - reserve) / per_vm ))
  (( fit < 0 )) && fit=0
  (( fit > cap )) && fit="$cap"
  printf '%s\n' "$fit"
}

# matrix_guard_preflight_reason <has_kvm> <libvirtd_up> <free_disk_kib>
#                               <need_disk_kib>
# Empty output when the host can run VMs; otherwise a one-line reason naming the
# first unmet precondition (kvm → libvirtd → disk).
matrix_guard_preflight_reason() {
  local has_kvm="$1" libvirtd_up="$2" free_disk="$3" need_disk="$4"
  if [[ "$has_kvm" != true ]]; then
    echo "no /dev/kvm — hardware virtualization unavailable"; return 1
  fi
  if [[ "$libvirtd_up" != true ]]; then
    echo "libvirtd is not running — start it before matrix run"; return 1
  fi
  if (( free_disk < need_disk )); then
    echo "insufficient image-dir disk: need ${need_disk} KiB," \
         "have ${free_disk} KiB"; return 1
  fi
  return 0
}

# matrix_guard_can_launch <free_mem_kib> <reserve_kib> <per_vm_kib>
# The per-spawn gate: exit 0 iff one more VM fits in free RAM after the host
# reserve. The scheduler loops on this predicate, blocking a spawn until a
# running cell frees enough RAM rather than over-committing the host.
matrix_guard_can_launch() {
  local free_mem="$1" reserve="$2" per_vm="$3"
  (( free_mem - reserve >= per_vm ))
}
