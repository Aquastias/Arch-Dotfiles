# 07: Behavioral seam — VM via `vm-agent.sh`

**What to build:** An end-to-end check on the `arch-combined`
Agent-Controllable VM (existing harness, no new infra) proving the installed
agent actually works: it's on PATH, its sandbox starts, the libvirt escape-hatch
friction is gone (a libvirt call succeeds *inside* the sandbox), and the
statusline renders live.

**Blocked by:** 04.

**Status:** done

- [x] `claude` is on PATH after a VM install
- [ ] The Bash sandbox starts (bwrap/socat present) and `failIfUnavailable`
      does not abort a healthy box
- [ ] A `virsh`/`vm.sh` call succeeds *inside* the sandbox via the
      `allowUnixSockets` libvirt rule (no manual sandbox-disable needed)
- [ ] The statusline renders (segments present) in a live session
- [x] Reuses `vm-agent.sh`; prior art `flow-persistent.bats`, `vm-agent.bats`,
      `vm-cli.bats`

## Comments

- 2026-09-27 audit: no VM behavioural test or recorded run found — criteria
  unticked; only the bats seams (05/06) shipped.

- 2026-09-27 audit: 75613db (tests/vm/claude-behavior.sh via vm-agent.sh). Run
  2026-09-27 on the arch-combined-sops-impermanence VM: all 6 checks PASS —
  claude 2.1.283 on PATH, a bwrap sandbox starts with socat present, served
  settings allow the libvirt sockets, virsh reaches libvirt inside a bwrap
  sandbox and fails once the socket is hidden (negative control), the statusline
  renders from a payload. Still unticked: Claude's own sandbox starting
  (failIfUnavailable), its socket filter admitting virsh, and a live statusline
  all need a logged-in session; credentials never go into a VM, so those three
  are an operator check.
