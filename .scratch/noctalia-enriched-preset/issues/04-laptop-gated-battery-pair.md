# 04 — Laptop-gate the battery pair

**What to build:** On a laptop, the session comes up with
`battery-power-management` + `battery-widget` enabled; on a desktop they are
absent. Gating is by presence of `/sys/class/power_supply/BAT*` (the installer
runs in `arch-chroot` on the target, so `/sys` is live hardware), overridable by
an explicit `laptop` bool in `install-niri.jsonc` (unset ⇒ detect, set ⇒ wins).
`battery-threshold` is not shipped (redundant with `battery-power-management`).
The Package Resolver reflects the gate.

**Blocked by:** 03.

**Status:** ready-for-agent

- [ ] Battery pair seeds when `/sys/class/power_supply/BAT*` is present, absent
      when not.
- [ ] The `laptop` bool overrides detection both ways.
- [ ] `battery-threshold` is never seeded.
- [ ] The Package Resolver reports the battery pair only when the gate is on.
- [ ] `niri-adapter.bats` covers battery-present, battery-absent, and both
      override directions.
