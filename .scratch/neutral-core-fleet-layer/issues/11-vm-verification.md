# 11: VM verification

**What to build:** proof on a real install that both paths behave. Per the VM
agent workflow (one VM at a time, sandbox disabled): `arch-kde` still installs
the curated environment, and a blank Guided install picking one desktop lands
stock with no personal software. See PRD and [[ADR 0157]].

**Blocked by:** 06 (`*-pure` neutral user), 09 (Trim stock KDE), 10 (Neutral
Guided Launch Presets)

**Status:** ready-for-agent

- [ ] `arch-kde` VM install: curated apps, captured settings, theme present
- [ ] Blank Guided VM install with KDE: stock Plasma, no claude/pi/docker/
      Fleet Layer packages, user shell bash
- [ ] VM stopped afterwards; findings appended under `## Comments`
