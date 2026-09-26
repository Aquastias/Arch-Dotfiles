# 03: Indicators

**What to build:** an in-repo Indicator store (kind
pkgbase|npm|domain|sha256|path, value, campaign, window, source), matched by
the vetter. A package-name Indicator is critical only when the commit falls
inside its campaign window, and suspicious until pinned otherwise. Seed
data comes from primary sources: the official Arch Atomic Arch list
(aur-general thread / md.archlinux.org) and the Chaos RAT and
google-chrome-stable advisories. lenucksi/aur-malware-check `iocs.txt`
fills gaps. Every line is tagged with its source. An optional refresh
subcommand pulls community lists into the repo for review; there is never
a live fetch at runtime. See PRD stories 15, 16, 54-56.

**Blocked by:** 01.

**Status:** ready-for-agent

- [ ] Any npm/domain Indicator hit is critical.
- [ ] A package-name hit inside the window is critical; outside the window
      it is suspicious (the clock is overridable in tests).
- [ ] Every Indicator line carries a source; a bats guard rejects lines
      without one.
- [ ] The refresh command writes a reviewable diff to the repo and runs
      nothing at vet time.
- [ ] No lenucksi code is vendored (it is GPL-3 and Python); data only.
