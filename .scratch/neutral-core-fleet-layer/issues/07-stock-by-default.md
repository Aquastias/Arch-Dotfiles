# 07: Stock by default

**What to build:** a picked desktop lands as the distro's stock environment
unless the operator opts into the curated one. The schema's `stock` Install
Default becomes `true`; the Fleet Layer sets `stock: false`; the curated VM
fixtures (`arch-kde`, `arch-niri`, `arch-hyprland`, `arch-combined*`,
`arch-audit`) set it explicitly so they keep testing curation. See PRD and
[[ADR 0157]].

**Blocked by:** 04 (Fleet Layer)

**Status:** done

- [x] Golden test (02) passes unchanged for `desktop` and `laptop`
- [x] A profile with a desktop and no `stock` key resolves stock
- [x] Curated VM fixtures resolve to the same set as before
- [x] The Guided `stock` Cycle Field shows the new default with no ●
- [x] install-config-defaults bats updated; suite green
