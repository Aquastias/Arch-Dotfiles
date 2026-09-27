# 01 — Timezone autodetected at install, drop the `UTC` pin

**What to build:** A fresh install lands on the correct clock without operator
input. At timezone-resolution time the installer autodetects the zone by geo-IP
and, when it cannot, falls back to `Europe/Bucharest`. An explicit or guided
timezone still wins. The `arch-combined` Host Profile no longer forces `UTC`, so
the reference box reflects the real resolver behaviour. (ADR 0118)

**Blocked by:** None — can start immediately.

**Status:** done

- [x] A new pure timezone resolver (modelled on the Printing Service resolver)
      resolves: explicit/guided value → geo-IP autodetect → `Europe/Bucharest`.
- [x] Autodetect uses a bounded curl to `https://ipapi.co/timezone`, matching the
      existing `--connect-timeout 2 --max-time 8` idiom.
- [x] The resolved zone is validated against `/usr/share/zoneinfo`; an
      invalid/empty result falls back to `Europe/Bucharest`.
- [x] A failed/offline fetch falls back to `Europe/Bucharest` (installer stays
      functional offline).
- [x] The network fetch is behind an injectable seam so tests never hit the
      network.
- [x] The `system.timezone: "UTC"` pin is removed from the `arch-combined` Host
      Profile.
- [x] `config/timezone.bats` (structured like `config/printing.bats`) covers:
      explicit wins; injected valid zone used; invalid/empty → fallback; offline
      → fallback.
- [x] Existing profile-loader / personal-profiles tests still pass with the pin
      removed.

## Comments

- 2026-09-27 doc sync: shipped in 8a32898, 54ecfba, 41a2188, 378db0b, a96edbc,
  e79ca17, 4352be4, dfc347d, 8f3795b, badf9e0, cd8f5a0, 840dfea, f598ff0 (ADR
  0118-0121).
