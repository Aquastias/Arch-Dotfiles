#!/usr/bin/env bats
# Tests for the Combination Matrix host-resource guard (combination-matrix/06,
# ADR 0046). Pure decision cores: facts in (MemAvailable, reserve, per-VM RAM,
# cap; probed kvm/libvirtd/disk facts; free RAM), decision out. No probing, no
# TTY, no VM. Behaviour under test is the scheduling decision, never how it is
# computed.

setup() {
  OS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export OS_DIR
  # shellcheck source=../../lib/matrix/guard.sh
  source "$OS_DIR/lib/matrix/guard.sh"
}

# ── AC1: max_parallel = floor((avail − reserve) / per_vm), clamped to cap ─────

@test "max_parallel: fits several VMs, clamped to the cap" {
  # 40 GiB avail − 4 GiB reserve = 36 GiB; /8 GiB = 4 fit, capped at 3.
  run matrix_guard_max_parallel $((40*1024*1024)) $((4*1024*1024)) \
    $((8*1024*1024)) 3
  [ "$status" -eq 0 ]
  [ "$output" -eq 3 ]
}

@test "max_parallel: RAM below one VM after reserve → 0 (never negative)" {
  # 10 GiB avail − 4 GiB reserve = 6 GiB; one 8 GiB VM does not fit.
  [ "$(matrix_guard_max_parallel $((10*1024*1024)) $((4*1024*1024)) \
    $((8*1024*1024)) 3)" -eq 0 ]
  # reserve far exceeds available → clamp to 0, not a negative count.
  [ "$(matrix_guard_max_parallel $((2*1024*1024)) $((20*1024*1024)) \
    $((8*1024*1024)) 3)" -eq 0 ]
}

# ── AC2: preflight aborts with a clear reason before any VM starts ────────────

@test "preflight_reason: kvm + libvirtd + enough disk → empty (OK)" {
  # has_kvm libvirtd_up free_disk_kib need_disk_kib
  run matrix_guard_preflight_reason true true $((100*1024*1024)) \
    $((40*1024*1024))
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "preflight_reason: each unmet precondition → a distinct clear reason" {
  run matrix_guard_preflight_reason false true $((100*1024*1024)) \
    $((40*1024*1024))
  [ "$status" -ne 0 ]
  [[ "$output" == *kvm* ]]

  run matrix_guard_preflight_reason true false $((100*1024*1024)) \
    $((40*1024*1024))
  [ "$status" -ne 0 ]
  [[ "$output" == *libvirtd* ]]

  run matrix_guard_preflight_reason true true $((10*1024*1024)) \
    $((40*1024*1024))
  [ "$status" -ne 0 ]
  [[ "$output" == *disk* ]]
}

# ── AC3: per-launch gate blocks a spawn until free RAM allows it ──────────────

@test "can_launch: true iff one VM fits in free RAM after the reserve" {
  # free_mem_kib reserve_kib per_vm_kib
  # 20 GiB free − 4 GiB reserve = 16 GiB ≥ 8 GiB → launch.
  run matrix_guard_can_launch $((20*1024*1024)) $((4*1024*1024)) \
    $((8*1024*1024))
  [ "$status" -eq 0 ]
  # 10 GiB free − 4 GiB reserve = 6 GiB < 8 GiB → block.
  run matrix_guard_can_launch $((10*1024*1024)) $((4*1024*1024)) \
    $((8*1024*1024))
  [ "$status" -ne 0 ]
}
