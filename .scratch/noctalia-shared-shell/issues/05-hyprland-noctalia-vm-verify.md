# 05 — Hyprland+Noctalia VM `desktop-verify` cell

**What to build:** the install matrix proves a fresh Hyprland+Noctalia box comes
up as a working session, the same way the niri+Noctalia cell does. A
greeter-launched Hyprland session must reach a running compositor with the
Noctalia shell autostarted, taking DRM master via seatd, with the lock reachable
via `ext-session-lock`.

**Blocked by:** 03

**Status:** ready-for-agent

**As-built:** added the curated `arch-hyprland` host profile
(`hosts/vm/arch-hyprland/`, desktop=hyprland + wayland_shell=noctalia) and the
`vm/profiles/desktop/hyprland.jsonc` VM profile, mirroring `arch-niri`. The
seed-generator already derives the Hyprland session block (tag `HYPR`, file
`hyprland.desktop`, `Hyprland` compositor proc) and the desktop-verify prober
waits for the compositor + a wayland socket, so the cell emits
`===HYPR-SESSION-OK===`. The host profile is schema-validated by the real-profile
loop. **Note:** the actual VM boot cannot run in this environment; the config +
wiring are in place for CI/local VM runs.

- [x] A curated Hyprland + `wayland_shell=noctalia` VM cell exists and its host
      profile validates against the closed schema.
- [x] `desktop-verify` handles the Hyprland session (compositor + wayland socket
      → `===HYPR-SESSION-OK===`), via the existing generic machinery.
- [ ] Noctalia-daemon liveness is asserted in the prober (future enhancement —
      the prober currently proves the compositor, not the shell daemon).
- [ ] The lock-before-suspend known-issue is confirmed on a real VM run
      (cannot run here).
