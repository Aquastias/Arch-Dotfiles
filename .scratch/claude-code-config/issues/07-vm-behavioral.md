# 07: Behavioral seam — VM via `vm-agent.sh`

**What to build:** An end-to-end check on the `arch-combined`
Agent-Controllable VM (existing harness, no new infra) proving the installed
agent actually works: it's on PATH, its sandbox starts, the libvirt escape-hatch
friction is gone (a libvirt call succeeds *inside* the sandbox), and the
statusline renders live.

**Blocked by:** 04.

**Status:** ready-for-agent

- [ ] `claude` is on PATH after a VM install
- [ ] The Bash sandbox starts (bwrap/socat present) and `failIfUnavailable`
      does not abort a healthy box
- [ ] A `virsh`/`vm.sh` call succeeds *inside* the sandbox via the
      `allowUnixSockets` libvirt rule (no manual sandbox-disable needed)
- [ ] The statusline renders (segments present) in a live session
- [ ] Reuses `vm-agent.sh`; prior art `flow-persistent.bats`, `vm-agent.bats`,
      `vm-cli.bats`
