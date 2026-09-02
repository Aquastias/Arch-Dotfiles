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

**Status:** done

- [x] `vm.sh` preflight (`_ensure_libvirt_reachable`) emits a recognizable
      "libvirt unreachable (sandbox?)" signal when libvirtd is up but virsh
      can't connect, and a plain "libvirt unreachable" when the daemon is down.
- [x] `docs/agents/vm-sandbox.md` states the retry-outside-sandbox operating
      rule.
- [x] `CLAUDE.md` references it under Agent skills (`### VM sandbox`).
