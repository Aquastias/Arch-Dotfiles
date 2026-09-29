# 08: Sessions phase

**What to build:** per variant, log into each compositor in the desktop
set (KDE, niri, Hyprland) via VM Agent Control `session`, collect the user
journal + compositor log, and screenshot. `report` gains a visual-review
section listing screenshots for the fixing agent.

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] Each compositor session started; failure to start is a Finding
- [ ] User journal + compositor log per session, tagged `sessions`
- [ ] Screenshot per session in the run folder
- [ ] `findings.md` visual-review section; bats via fixture run folder
