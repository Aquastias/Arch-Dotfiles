# 11: VM verification

**What to build:** proof on a real install that both paths behave. Per the VM
agent workflow (one VM at a time, sandbox disabled): `arch-kde` still installs
the curated environment, and a blank Guided install picking one desktop lands
stock with no personal software. See PRD and [[ADR 0157]].

**Blocked by:** 06 (`*-pure` neutral user), 09 (Trim stock KDE), 10 (Neutral
Guided Launch Presets)

**Status:** done

- [x] `arch-kde` VM install: curated apps, captured settings, theme present
- [x] Blank Guided VM install with KDE: stock Plasma, no claude/pi/docker/
      Fleet Layer packages, user shell bash
- [x] VM stopped afterwards; findings appended under `## Comments`

## Comments

- 2026-10-18 — `vm.sh --guided --profile single/guided-stock-kde --verify-boot
  --recreate --local`: install exit 0, `FIRSTBOOT-OK`. Replay answered only
  `desktop=kde` (+ fallback `users=stock`). Install log: `plasma-meta` installed;
  none of konsole/dolphin, papirus, weather widget, steam, firefox, claude, pi,
  docker, vscodium, neovim, kitty, Nerd fonts, ttf-ms-fonts, firewalld, clamav,
  noctalia. Timezone resolved at install (Europe/Bucharest via geo-IP/fallback).
- 2026-10-18 — `vm.sh --profile desktop/kde --recreate --local` (`arch-kde`):
  installed + booted; KDE session shows the captured panel (Default/Dev
  activities, weather widget); `pacman -Q` has plasma-meta, papirus, the weather
  widget, dolphin, konsole, kitty, claude-code; `aquastias` shell `/bin/zsh`.
  VM stopped afterwards.
