# 07: Behavioral seam — VM via `vm-agent.sh`

**What to build:** An end-to-end check on the `arch-combined`
Agent-Controllable VM (existing harness, no new infra) proving the installed
agent actually works: it's on PATH, its sandbox starts, the libvirt escape-hatch
friction is gone (a libvirt call succeeds *inside* the sandbox), and the
statusline renders live.

**Blocked by:** 04.

**Status:** done

- [x] `claude` is on PATH after a VM install
- [x] The Bash sandbox starts (bwrap/socat present) and `failIfUnavailable`
      does not abort a healthy box
- [x] A `virsh`/`vm.sh` call succeeds *inside* the sandbox via the
      `allowUnixSockets` libvirt rule (no manual sandbox-disable needed)
- [x] The statusline renders (segments present) in a live session
- [x] Reuses `vm-agent.sh`; prior art `flow-persistent.bats`, `vm-agent.bats`,
      `vm-cli.bats`

## Comments

- 2026-09-27 doc sync: shipped in 6521bc3, 2bb7784, 6e78829, 2711118, 8d7adf8,
  0529dd6, 4039310, 88a7516, 1f74b30 (ADR 0133).
