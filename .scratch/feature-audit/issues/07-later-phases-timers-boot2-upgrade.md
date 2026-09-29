# 07: Later phases: timers, second boot, upgrade

**What to build:** per variant, after the first-boot phases: force-start
every enabled timer's unit + 10-min idle soak, then reboot (`boot2`:
impermanence rollback, persist, SOPS decrypt proven), then `pacman -Syu` +
reboot (`upgrade`). Each phase collected and tagged.

**Blocked by:** 02

**Status:** done

- [x] Timer units started; failures collected as Findings
- [x] Soak duration configurable, default 10 min
- [x] boot2 checks rollback/persist/SOPS; failures are Findings
- [x] Upgrade phase collects pacman/hook output + post-reboot signals,
      tagged `phase=upgrade`
