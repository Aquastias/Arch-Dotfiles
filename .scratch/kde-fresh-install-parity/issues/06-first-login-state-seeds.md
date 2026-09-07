# 06 — First-Login State: audio, login background, welcome suppression

**What to build:** The pieces of the reference-box setup that cannot live in a
captured `.config` file are reconstructed at install/first-login: audio line
in/out come up at 100%, the SDDM login background matches the Horos lock-screen
wallpaper, and the Plasma Welcome Center stays suppressed even after a
`plasma-welcome` upgrade. (ADR 0121)

**Blocked by:** None — can start immediately. (Coordinates with ticket 03's
captured `plasma-welcomerc`; at install the dynamic version write is last-wins,
so order does not matter.)

**Status:** ready-for-agent

- [ ] An idempotent first-login autostart sets `@DEFAULT_AUDIO_SINK@` and
      `@DEFAULT_AUDIO_SOURCE@` to 100% via `wpctl` (no vendored device state).
- [ ] The SDDM Breeze theme `Background` is set to the Horos wallpaper, in the
      KDE adapter's own SDDM drop-in (merges with the Display Manager Adapter's
      file, ADR 0069).
- [ ] `plasma-welcomerc [General] LastSeenVersion` is written to the installed
      `plasma-welcome` version (`pacman -Q`) at install time; the `Hidden=true`
      autostart is retained.
- [ ] `extras/kde-adapter.bats` asserts: the volume autostart `.desktop` is
      written; the SDDM drop-in sets the Horos `Background`; `LastSeenVersion` is
      written from the stubbed `pacman -Q`.
