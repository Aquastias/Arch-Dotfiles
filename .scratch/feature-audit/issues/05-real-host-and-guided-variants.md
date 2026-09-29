# 05: Real-host + guided variants

**What to build:** variants that install the real hosts `desktop`,
`laptop`, `core` as-is on VM disks, and one guided (menu-driven) install via
the existing guided flow.

**Blocked by:** 04

**Status:** ready-for-agent

- [ ] Manifest supports a real-host reference as a variant
- [ ] desktop, laptop, core resolve in `check` against VM disks
- [ ] Guided variant drives the menu unattended and installs
- [ ] Each runs through the same collectors + report
