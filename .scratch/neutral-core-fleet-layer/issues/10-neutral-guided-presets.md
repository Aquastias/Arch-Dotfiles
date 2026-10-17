# 10: Neutral Guided Launch Presets and no-user gate

**What to build:** a blank Guided session preselects nothing personal:
hostname `archlinux`, no Primary User, timezone autodetected ([[ADR 0118]]),
no desktop, Security & Backup Extras off. Proceed is refused with a clear
notice until a user exists (interactive and headless replay). A permanent
leak guard asserts the blank Effective Config holds nothing from the Fleet
Layer or `aquastias`. See PRD and [[ADR 0157]].

**Blocked by:** 04 (Fleet Layer), 05 (Neutral User Core), 07 (Stock by
default), 08 (Neutral fonts and mirrors)

**Status:** ready-for-agent

- [ ] Blank replay with one created user: no Fleet Layer package/Host Program,
      no `aquastias` program, hostname `archlinux`, no desktop, extras off,
      neutral fonts and mirrors
- [ ] Proceed with no user is refused in both front-ends
- [ ] Picking `desktop` in Guided still reproduces the golden (02)
- [ ] guided-seed bats rewritten for the neutral presets; CONTEXT.md Guided
      Launch Preset entry updated; suite green
