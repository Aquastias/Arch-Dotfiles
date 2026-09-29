# 05: Real-host + guided variants

**What to build:** variants that install the real hosts `desktop`,
`laptop`, `core` as-is on VM disks, and one guided (menu-driven) install via
the existing guided flow.

**Blocked by:** 04

**Status:** done

- [x] Manifest supports a real-host reference as a variant
- [x] desktop, laptop, core resolve in `check` against VM disks
- [x] Guided variant drives the menu unattended and installs
- [x] Each runs through the same collectors + report

## Comments

- `core` is Host Core, a reserved layer (`load_profile core` refuses), so it
  is not a variant: every host merges over it. desktop, laptop and the
  guided (manual-partitioning) install are variants; the guided one runs
  the disposable guided flow (install + boot-verify only).
