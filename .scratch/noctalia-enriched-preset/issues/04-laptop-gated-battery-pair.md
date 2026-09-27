# 04 — Laptop-gate the battery pair

**What to build:** On a laptop, the session comes up with
`battery-power-management` + `battery-widget` enabled; on a desktop they are
absent. Gating is by presence of `/sys/class/power_supply/BAT*` (the installer
runs in `arch-chroot` on the target, so `/sys` is live hardware), overridable by
an explicit `laptop` bool in `install-niri.jsonc` (unset ⇒ detect, set ⇒ wins).
`battery-threshold` is not shipped (redundant with `battery-power-management`).
The Package Resolver reflects the gate.

**Blocked by:** 03.

**Status:** done

- [x] Battery pair seeds when `/sys/class/power_supply/BAT*` is present, absent
      when not.
- [x] The `laptop` bool overrides detection both ways.
- [x] `battery-threshold` is never seeded.
- [x] The Package Resolver reports the battery pair only when the gate is on.
- [x] `niri-adapter.bats` covers battery-present, battery-absent, and both
      override directions.

## Comments

- 2026-09-27 doc sync: shipped in 16a1ec5, 10b2eab, 06ab093, 3f61836, 58c1323,
  a30056f (ADR 0093); Rosé Pine default superseded by ADR 0101/0109.
