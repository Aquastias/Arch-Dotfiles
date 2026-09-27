# 02 — Session control: session / logout / reboot

**What to build:** let the agent log into any session, log out, and reboot a
headless [[Agent-Controllable VM]]. `session <niri|hyprland|kde>` writes a
CLI-owned, DM-agnostic autologin drop-in for the resolved greeter — sddm
`[Autologin]` when KDE is in the set, greetd `[initial_session]` for a KDE-free
compositor set (ADR 0069/0091) — then reboots and waits until the chosen session
is ready. `logout` ends the current session via `loginctl terminate-session`
(re-autologins a fresh session, no full reboot). `reboot` restarts and waits.
The CLI owns its drop-in and never mutates the seeded DM config; the default
boot session is the first compositor in the desktop set.

**Blocked by:** 01 — CLI skeleton (needs `ready`, connect, sudo).

**Status:** done

- [x] `session kde` boots the VM into Plasma; `session niri` / `session hyprland`
      boot the respective compositor — each waits until the session is actually
      up before returning.
- [x] Autologin is written to a CLI-owned drop-in (sddm or greetd per the
      resolved greeter), leaving the seeded DM config untouched.
- [x] `logout` terminates the session and a fresh session re-autologins without a
      full reboot; `reboot` restarts and waits ready.
- [x] Default boot session resolves to the first compositor in the desktop set.
- [x] `vm-agent.bats` asserts the pure logic: autologin-config generation
      (correct sddm `[Autologin]` and greetd `[initial_session]` for each of
      niri/Hyprland/KDE), session-name→`.desktop` mapping, and default-session
      resolution.
- [x] Hand-verified on `arch-combined` (niri↔KDE↔hyprland round-trip).

## Comments

- 2026-09-27 doc sync: shipped in 24258ce, 51d7a0d (ADR 0117).
