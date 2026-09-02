#!/usr/bin/env bats
# Tests for vm/lib/host-capacity.sh — the host-safety capacity policy (ADR
# 0099): the concurrent-VM cap from RAM AND cores, the force-serial rule for
# heavy VMs, and the single-VM admit gate that refuses an oversized launch. Pure
# fact-in / decision-out, so no VM and no host probing here.

setup() {
  # shellcheck source=../../vm/lib/host-capacity.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/host-capacity.sh"
}

# ── host_capacity_max_vms: min(RAM-fit, cores), clamped to [1, cap] ───────────

@test "max_vms: RAM is the binding constraint" {
  # 10 GiB free, 8 cores, 4 GiB/VM, cap 8 → RAM-fit 2 < cores 8 → 2
  run host_capacity_max_vms 10240 8 4096 8
  [ "$output" -eq 2 ]
}

@test "max_vms: cores are the binding constraint" {
  # 64 GiB free, 2 cores, 4 GiB/VM, cap 8 → RAM-fit 16, cores 2 → 2
  run host_capacity_max_vms 65536 2 4096 8
  [ "$output" -eq 2 ]
}

@test "max_vms: clamped to the conservative cap" {
  # 64 GiB free, 32 cores, 4 GiB/VM, cap 2 → min(16,32)=16 clamped to 2
  run host_capacity_max_vms 65536 32 4096 2
  [ "$output" -eq 2 ]
}

@test "max_vms: never below 1 even when RAM is tight" {
  # 1 GiB free, 4 cores, 4 GiB/VM → RAM-fit 0 → floored to 1
  run host_capacity_max_vms 1024 4 4096 8
  [ "$output" -eq 1 ]
}

@test "max_vms: uses module defaults for per_vm and cap" {
  # defaults: per_vm 4096, cap 2. 16 GiB free, 8 cores → min(4,8)=4 clamped to 2
  run host_capacity_max_vms 16384 8
  [ "$output" -eq 2 ]
}

# ── host_capacity_force_serial: heavy VMs never stack ─────────────────────────

@test "force_serial: graphical VM forces serial" {
  run host_capacity_force_serial true false false
  [ "$status" -eq 0 ]
}

@test "force_serial: persistent VM forces serial" {
  run host_capacity_force_serial false true false
  [ "$status" -eq 0 ]
}

@test "force_serial: desktop-verify forces serial" {
  run host_capacity_force_serial false false true
  [ "$status" -eq 0 ]
}

@test "force_serial: a plain headless VM does not force serial" {
  run host_capacity_force_serial false false false
  [ "$status" -ne 0 ]
}

# ── host_capacity_admit: single-VM safe-fraction gate ─────────────────────────

@test "admit: a VM within the safe fraction is admitted" {
  # 4 GiB VM on a 16 GiB host at 80% → 4096*100=409600 <= 16384*80=1310720 → ok
  run host_capacity_admit 4096 16384 80
  [ "$status" -eq 0 ]
}

@test "admit: a VM over the safe fraction is refused" {
  # 14 GiB VM on a 16 GiB host at 80% → 1400*... exceeds → refuse
  run host_capacity_admit 14336 16384 80
  [ "$status" -ne 0 ]
}

@test "admit: exactly at the threshold is admitted" {
  # 8 GiB VM on 10 GiB host at 80% → 8192*100=819200 == 10240*80=819200 → ok
  run host_capacity_admit 8192 10240 80
  [ "$status" -eq 0 ]
}

@test "admit: unknown/zero host RAM is refused" {
  run host_capacity_admit 4096 0 80
  [ "$status" -ne 0 ]
}

@test "admit: non-numeric input is refused" {
  run host_capacity_admit 4096 "lots" 80
  [ "$status" -ne 0 ]
}

@test "admit: uses the default safe percentage" {
  # default 80%. 4 GiB VM on 16 GiB host → admitted.
  run host_capacity_admit 4096 16384
  [ "$status" -eq 0 ]
}
