# 03: Explicit `display_manager: noctalia-greeter`, end to end

**What to build:** An operator can choose `noctalia-greeter` as the Display
Manager and boot to it. The value is accepted at config-load (aborts on an
empty desktop set, like the other DMs; allowed on any non-empty set), offered
in the menu and the Guided Display Manager row, and reported by the Package
Resolver's `display-manager` set as `greetd noctalia-greeter`. A new Display
Manager Adapter installs it with pacman from `extra`, runs
`noctalia-greeter-apply-appearance --setup-system`, writes the greetd config
(launching `noctalia-greeter-session`) via the shared helper, and enables
greetd. Shell → greeter appearance sync stays manual; no passwordless sync
([ADR 0158]).

**Blocked by:** 01, 02, and external: `noctalia-greeter` available in Arch
`extra` (`pacman -Si noctalia-greeter` resolves; was `extra-testing` only on
2026-10-19). Cleared 2026-10-19: 1.6.0 in `extra`.

**Status:** done

- [x] Config-load accepts `noctalia-greeter`; empty desktop set aborts.
- [x] Menu + Guided row offer it; resolver set matches what the adapter
      installs.
- [x] Adapter installs via pacman only (no AUR, no testing repo).
- [x] `/var/lib/noctalia-greeter` exists, owned by the greeter user.
- [x] VM run boots to noctalia-greeter; session list = curated sessions only;
      login into niri and Hyprland works; agent autologin still works.
- [x] CONTEXT.md Display Manager Adapter entry lists the third adapter.

## Comments

VM proof 2026-10-19 (local HEAD d0c5ad7), `desktop/hyprland` and
`desktop/niri` (both `auto`): greetd enabled + active, `command =
"/usr/bin/noctalia-greeter-session"`, state dir + greeter.toml/sync.toml owned
`greeter:greeter`; `noctalia-greeter sessions` = `Hyprland` / `Niri` only.
Real password login typed at the greeter (QMP keys) started Hyprland and niri
sessions with Noctalia (screenshots). Agent `session hyprland` autologin
works. The greeter itself can't be screenshotted (its compositor lacks
screencopy).
