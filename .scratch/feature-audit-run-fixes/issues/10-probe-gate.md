# 10: Probe Gate

**What to build:** A probe check declares the Host Profile conditions it
needs; the guest gets the variant's profile; an unmet gate prints SKIP with
the reason; the report lists skipped checks. Gate apparmor/bluetooth on
services-off (F591-F595), xdg dirs on stock (F379-F384), smartd on kde-pure
(F589). Amends ADR 0152.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] New probe-lib bats: fixture profiles (stock, no shell, services off) →
SKIP; base → runs
- [ ] report.bats: skips listed, not Findings
- [ ] ADR 0152 amended
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone
(services-off, hyprland-pure, kde-pure)
