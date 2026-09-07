# KDE first-login state that cannot be a captured .config file

---
Status: accepted. **Complements ADR 0111/0120** (verbatim `~/.config` capture).
Covers the four pieces of the operator's setup that do **not** live in a
capturable per-user `.config` file — audio volume, the login-screen background,
welcome-center suppression, and the account avatar/name — and records the
mechanism chosen for each.
---

The operator's "make a fresh login look exactly like this box" request includes
state that verbatim `.config` capture cannot carry: runtime audio volume
(WirePlumber, device-keyed), the SDDM **login** background (system theme, not
per-user), welcome-center suppression (version-gated), and the account avatar +
display name (AccountsService + GECOS, per-user, not skel-portable as-is).

## Decision

- **Audio line in/out at 100%** — a small, idempotent first-login autostart runs
  `wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0` and the same for
  `@DEFAULT_AUDIO_SOURCE@`. Chosen over vendoring `asound.state` /
  WirePlumber restore-stream state, which are device-keyed and wrong on
  different audio hardware.

- **Login-screen background = lock-screen wallpaper (Horos)** — set the SDDM
  Breeze theme's `Background` to the Horos wallpaper, in the KDE adapter's own
  SDDM drop-in (merges with the Display Manager Adapter's file, ADR 0069). The
  lock screen already carries Horos via the captured `kscreenlockerrc`; this
  makes login match.

- **Welcome center stays suppressed** — keep the `Hidden=true`
  `autostart/plasma-welcome.desktop` seed **and** write `plasma-welcomerc`
  `[General] LastSeenVersion` to the **installed** `plasma-welcome` version
  (`pacman -Q`) at install time. The autostart alone proved insufficient; the
  version gate is plasma-welcome's own "already seen" check, so writing the live
  version is robust across upgrades in a way a captured static version is not.

- **Avatar + display name** — seed the avatar image to `/etc/skel/.face` and
  write the primary user's AccountsService record + icon at user creation; set
  the GECOS full name (default `Alex`) from a config field for the primary user.
  Per-user by nature, so it is applied to the primary user rather than blindly to
  every future account.

## Considered options

- **Night light Automatic via geoclue** (belongs here as the rejected sibling) —
  rejected: `geoclue` is not even installed, its network-location backend
  (Mozilla Location Service) was shut down in 2024, and a VM has no WiFi/GPS
  fix, so Automatic silently never shifts. ADR 0120 pins Location + fixed coords
  instead.
- **Vendor WirePlumber/ALSA state** for volume — rejected: device-keyed, wrong
  on other hardware.
- **Capture avatar/name as `.config`** — impossible: they live in
  `/var/lib/AccountsService` and the passwd GECOS, not `~/.config`.

## Consequences

- These seeds run at install/first-login, not via verbatim copy, so they are the
  one part of the "looks like arch-combined" guarantee that is *reconstructed*
  rather than *copied*. Documented so a future reader does not expect them in the
  captured skel set.
- The volume autostart and welcome version write are host-agnostic; the avatar/
  name seed is scoped to the primary user only.
