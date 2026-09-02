# 04 — Host-safety concurrency cap + launch preflight

**What to build:** The harness never runs so many VMs that it crashes the host.
A pure function maps `(free_ram, cores)` to a maximum number of concurrent VMs
(~4 GB/VM budget, clamped to a conservative default), and
graphical/desktop-verify/persistent VMs are forced to run **serially**
regardless of the cap. A launch preflight refuses to start a VM — with a clear
message — when the projected RAM would exceed a safe fraction of host RAM.

Anchored by ADR 0099.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] A pure function computes the max-concurrent-VMs cap from free RAM and core
      count, with a conservative default clamp.
- [ ] Graphical / desktop-verify / persistent VMs are forced serial regardless
      of the cap.
- [ ] A launch preflight refuses to start a VM when projected RAM would exceed a
      safe fraction of host RAM, with a clear message.
- [ ] Seam-3 test: table-test `(free_ram, cores) → cap` with injected values;
      assert the serial-forcing rule and the preflight refusal threshold. No
      real host probing in the test.
