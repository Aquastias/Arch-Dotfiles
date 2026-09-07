# 04 — Idle/lock control: idle / lock / unlock

**What to build:** reversible, agent-driven control of idle and lock so long
operations aren't interrupted **and** lock behaviour stays debuggable. `idle
off` (the default state while the agent drives) holds a removable
idle/suspend/DPMS inhibitor; `idle on` restores normal behaviour. `lock` and
`unlock` drive `loginctl lock-session`/`unlock-session` so the session lock —
Noctalia's on wlroots (ADR 0100) — can be exercised on demand. Nothing is
permanently disabled in the guest.

**Blocked by:** 01 — CLI skeleton (connect, env).

**Status:** ready-for-agent

- [ ] `idle off` inhibits idle/suspend/DPMS (default while driving); `idle on`
      removes the inhibitor and normal locking resumes.
- [ ] `lock` locks the running session; `unlock` unlocks it — verified against a
      wlroots (Noctalia) session and a Plasma session.
- [ ] No guest config is permanently altered — the inhibitor is removable and
      lock/idle remain fully testable after `idle on`.
- [ ] Hand-verified on `arch-combined`.
