# 06 — Sandbox fallback: `vm.sh` signal + agent doc

**What to build:** When an agent runs the harness under a sandbox that blocks
the libvirt socket, it knows to retry outside the sandbox. `vm.sh` preflight
emits a recognizable "libvirt unreachable (sandbox?)" message that
distinguishes a sandbox-blocked socket from libvirt genuinely being down. The
operating rule — *if `virsh`/libvirt is unreachable under sandbox, retry the
same command with the sandbox disabled* — is documented under `docs/agents/`
and referenced from `CLAUDE.md`, because a script cannot disable its caller's
sandbox.

Anchored by ADR 0099.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `vm.sh` preflight emits a recognizable "libvirt unreachable (sandbox?)"
      signal, distinguishing a blocked socket from libvirt being down where it
      can.
- [ ] A `docs/agents/` doc states the retry-outside-sandbox operating rule.
- [ ] `CLAUDE.md` references the new agent doc under its Agent skills section.
