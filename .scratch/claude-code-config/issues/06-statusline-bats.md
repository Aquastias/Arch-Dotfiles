# 06: Statusline seam — `statusline.bats`

**What to build:** A unit test that pins the statusline's rendering contract —
it is a pure JSON→string function, so fixture payloads in, expected segments
out. Guards the meter/cost swap and the new native-field segments against
regression. The approved prototype
(`.scratch/claude-code-config/statusline-prototype.sh`) already encodes the
expected shape.

**Blocked by:** 03.

**Status:** ready-for-agent

- [ ] Fixture payloads for: clean, dirty tree, near-limit, subscription, and
      API-billed states
- [ ] Asserts the 5h-meter ↔ `$cost` swap keyed on billing type
- [ ] Asserts the native cache-ratio segment (no transcript dependency)
- [ ] Asserts `effort.level`, the dirty red dot (with leading space), and
      +green / −red lines
- [ ] Asserts emoji icons render (segment presence)
- [ ] Passes with and without `ccusage` present (graceful-degrade path)
