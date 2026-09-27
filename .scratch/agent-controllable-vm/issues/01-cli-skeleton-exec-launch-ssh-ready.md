# 01 — CLI skeleton: connect, exec, launch, ssh, ready

**What to build:** the [[VM Agent Control]] CLI's foundation — the "run things in
the guest" plumbing every other verb builds on. `vm-agent.sh` selects a
persistent-flow [[VM Harness]] VM the same way `vm.sh` does (`--profile`/name),
connects over the harness SSH key, and runs commands **with the running
session's environment auto-sourced** (from `/proc/<compositor-pid>/environ`, so
`WAYLAND_DISPLAY`/`DBUS_SESSION_BUS_ADDRESS` reach the live session). Verbs:
`exec <cmd…>` (env-aware), `launch <app…>` (detached, never holds the SSH
channel open), `ssh` (interactive guest shell), `ready` (block until the
session's compositor/shell is up). `virsh`/`ssh` follow the
`docs/agents/vm-sandbox.md` retry-with-sandbox-disabled rule; `sudo` uses the
piped harness password.

**Blocked by:** None — can start immediately.

**Status:** done

- [x] `vm-agent.sh` resolves a persistent VM by `--profile`/name and connects
      over the harness key, reusing existing `vm/lib` helpers (key path, IP
      discovery, profile resolution) rather than duplicating them.
- [x] `exec <cmd>` runs in the guest with the running session's env sourced
      automatically; e.g. `exec 'noctalia msg color-scheme-get'` returns the live
      theme with no hand-set `WAYLAND_DISPLAY`.
- [x] `launch <app>` starts a GUI app fully detached (returns immediately, app
      keeps running).
- [x] `ssh` drops into an interactive guest shell; `ready` blocks until the
      session is up (used by later verbs to avoid racing boot).
- [x] Unknown verb / no args prints usage and exits non-zero.
- [x] `.installer/tests/vm/vm-agent.bats` (new, mirroring `vm-cli.bats`) asserts
      verb dispatch/usage and the pure session-env-discovery helper — no live VM
      provisioned.
- [x] Hand-verified on the persistent `arch-combined` VM.

## Comments

- 2026-09-27 doc sync: shipped in 24258ce, 51d7a0d (ADR 0117).
