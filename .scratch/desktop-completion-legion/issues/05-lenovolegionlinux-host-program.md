# 05: LenovoLegionLinux Host Program

**What to build:** the laptop installs LenovoLegionLinux — the DKMS module
and the CLI/GUI tools — so the operator gets CPU temperature, fan curves and
Legion power modes. `legiond` stays disabled; power-profiles-daemon remains
the sole power-profile owner. Desktop is untouched. Parent: PRD (ADR 0161).

**Blocked by:** 04.

**Status:** done

- [x] New `system` Host Program per the program spec, AUR-sourced
      (`lenovolegionlinux-dkms-git`, `lenovolegionlinux-git`).
- [x] Both PKGBUILDs pass AUR vetting (ADR 0149) before first install.
- [x] No service enabled; program bats assert `legiond` is not enabled.
- [x] Declared only in the laptop profile's `host_programs`.
- [x] Laptop Fleet Golden regenerated; parity holds via ticket 04.
- [x] Grounded on Arch Wiki Laptop/Lenovo + Fan speed control and the
      upstream confirmed-model list (15ARH7H, JUCN55WW).

## Comments

- 2026-11-01: delivered as two laptop `packages.aur` entries, not a Host
  Program — Host Programs run as root via pacman and cannot reach the AUR
  (ADR 0041). Package-only: the module autoloads via ACPI/WMI ids, `legiond`
  is never enabled. Both PKGBUILDs pass aur-vet (0 findings); no allowlist
  row needed. ADR 0161 amended; ticket 04's exemption now filters these two
  AUR names.
