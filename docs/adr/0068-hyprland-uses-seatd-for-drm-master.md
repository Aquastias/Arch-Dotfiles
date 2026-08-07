# Hyprland uses seatd for DRM master, not logind

---
Status: accepted
---

The Hyprland adapter installs and enables `seatd`, and User Core adds every user
to the `seat` group. On the target AMD (Radeon 780M / gfx1103) laptop,
Hyprland's `aquamarine` backend **could not obtain DRM master through logind**:
every atomic KMS commit returned `atomic drm request: failed to commit:
Permission denied`, and the compositor retry-looped forever — the freeze /
"hotplug storm" / black screen chased for days. `loginctl` confirmed the launching
session was `Active` on `seat0` with `card1` as its master device and `fuser`/
`lsof` showed nothing else holding the card, yet logind still would not hand the
compositor master. kwin (KDE) was never affected — it takes master through a
different path — which is why KDE always worked on the identical machine while
Hyprland never did.

The fix is in aquamarine's own log: it **tries `seatd` first** (`connect to
/run/seatd.sock`) and only *falls back* to the failing logind path. Running
`seatd` (with the user in the `seat` group, which gates `/run/seatd.sock`) gives
aquamarine DRM master directly. Verified on hardware: a manual `Hyprland` launch
that had frozen every time came straight up once `seatd` was running and the
user was in `seat`.

This also finally explained the whole investigation: the earlier "Permission
denied" (under SDDM), the "hotplug rescan loop" (under greetd), and the instant
freezes were **all the same root cause** — a compositor with no DRM master. ADR
0067 (greetd owns the DM) was necessary but not sufficient; greetd got the
session active, but aquamarine still needed seatd to actually take master.

## Considered options

- **Debug the logind master handoff** — rejected: not root-caused (session was
  Active on the seat, nothing held the card, yet logind denied master), and
  aquamarine already prefers seatd, so `seatd` is the upstream-intended path.
- **Add users to `seat` unconditionally in User Core** — accepted and safe:
  `filter_existing_groups` / `_profiles_apply_user_groups` skip a group whose
  `getent` lookup fails, so `seat` applies only where seatd created the group
  (Hyprland hosts) and is silently dropped everywhere else.
- **Ship seatd fleet-wide** — rejected: it is Hyprland/aquamarine-specific; KDE
  uses logind fine, so `seatd` is installed and enabled only by the Hyprland
  adapter.

## Consequences

- `seatd.service` is enabled whenever Hyprland is installed (sole or KDE
  co-install); under impermanence the enablement is mirrored onto `/usr/lib` by
  the same machinery as any service (ADR 0061), surviving the rolled-back root.
- `seatd` coexists with logind; libseat prefers the seatd socket when present,
  so both greetd-launched sessions and manual TTY launches acquire DRM master.
- The bare-archinstall comparison that cracked it: minimal Arch + Hyprland
  happened to get master directly; the full installer's boot-to-graphical-target
  seat state did not — seatd removes that dependency entirely.
