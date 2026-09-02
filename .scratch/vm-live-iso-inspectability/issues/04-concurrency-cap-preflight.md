# 04 — Host-safety concurrency cap + launch preflight

**What to build:** The harness never runs so many VMs that it crashes the host.
A pure function maps `(free_ram, cores)` to a maximum number of concurrent VMs
(~4 GB/VM budget, clamped to a conservative default), and
graphical/desktop-verify/persistent VMs are forced to run **serially**
regardless of the cap. A launch preflight refuses to start a VM — with a clear
message — when the projected RAM would exceed a safe fraction of host RAM.

Anchored by ADR 0099.

**Blocked by:** None — can start immediately.

**Status:** done

- [x] A pure function computes the max-concurrent-VMs cap from free RAM and core
      count, with a conservative default clamp (`host_capacity_max_vms`).
- [x] Graphical / desktop-verify / persistent VMs are forced serial regardless
      of the cap (`host_capacity_force_serial`, unit-tested). A direct `vm.sh`
      launch is one VM (inherently serial); the concurrent scheduler (the
      Combination Matrix) already prevents host overcommit via its own
      RAM-gated guard (ADR 0046), left intact to avoid duplication.
- [x] A launch preflight refuses to start a VM when projected RAM would exceed a
      safe fraction of host RAM, with a clear message (`_vm_capacity_preflight`
      in `_vm_boot`, using `host_capacity_admit` against probed MemTotal) — the
      gate a direct `vm.sh` run previously lacked.
- [x] Seam-3 test: `host-capacity.bats` table-tests the cap, the serial-forcing
      rule, and the admit threshold with injected values (no host probing).
