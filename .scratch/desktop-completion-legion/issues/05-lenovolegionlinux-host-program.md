# 05: LenovoLegionLinux Host Program

**What to build:** the laptop installs LenovoLegionLinux — the DKMS module
and the CLI/GUI tools — so the operator gets CPU temperature, fan curves and
Legion power modes. `legiond` stays disabled; power-profiles-daemon remains
the sole power-profile owner. Desktop is untouched. Parent: PRD (ADR 0161).

**Blocked by:** 04.

**Status:** ready-for-agent

- [ ] New `system` Host Program per the program spec, AUR-sourced
      (`lenovolegionlinux-dkms-git`, `lenovolegionlinux-git`).
- [ ] Both PKGBUILDs pass AUR vetting (ADR 0149) before first install.
- [ ] No service enabled; program bats assert `legiond` is not enabled.
- [ ] Declared only in the laptop profile's `host_programs`.
- [ ] Laptop Fleet Golden regenerated; parity holds via ticket 04.
- [ ] Grounded on Arch Wiki Laptop/Lenovo + Fan speed control and the
      upstream confirmed-model list (15ARH7H, JUCN55WW).
