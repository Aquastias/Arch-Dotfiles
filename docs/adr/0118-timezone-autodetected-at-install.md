# Timezone is autodetected at install, Europe/Bucharest as fallback

---
Status: accepted. Corrects the `vm/arch-combined` profile's hard `UTC` pin and
promotes the guided default (`Europe/Bucharest`, seed.sh) to an install-time
**autodetect with fallback**. Sibling to the "output is machine-physical, never
hardcoded" stance of ADR 0110 — timezone is *machine-geographic*, so we resolve
it from the environment instead of committing a constant.
---

The reference box (`arch-combined`) came up on `UTC` because its Host Profile
pinned `system.timezone: "UTC"`, even though the operator's live box runs
`Europe/Bucharest` and the guided default already seeds `Europe/Bucharest`. The
operator asked the installer to "set the timezone automatically, if possible, or
Europe/Bucharest" — i.e. detect the real zone unattended, and only fall back to
a constant when detection is impossible.

## Decision

**Resolve the timezone at install time by geo-IP, with `Europe/Bucharest` as the
fallback.** The Arch ISO already has network up (mirrors, NTP — `timedatectl
set-ntp true` in `01-bootstrap-zfs.sh`), so a single lookup against an IP-geo
endpoint yields the IANA zone for the installing machine's public IP. On any
failure (no network, endpoint down, empty/invalid zone) the resolver falls back
to `Europe/Bucharest`, the operator's home zone and the existing guided default.
The **guided picker still wins** when the operator edits the field — autodetect
only fills the default so an unattended install lands on the right clock.

Correct the `arch-combined` Host Profile's `UTC` pin to match: the reference box
must reflect the fleet's real behaviour, not a stale constant.

## Considered options

- **Keep the static default / `UTC` pin** — rejected: it is exactly the gap the
  operator hit; an unattended install lands on the wrong clock.
- **Guided-picker only, no autodetect** — rejected: unattended/profile installs
  never open the picker, so they would keep the constant.
- **Ship a hardcoded `Europe/Bucharest` everywhere** — rejected as the *primary*
  path (it is only the fallback): dead-wrong for any machine installed outside
  that zone, the same failure mode ADR 0110 rejects for monitor modes.

## Consequences

- An unattended install phones an IP-geo service once — a deliberate, bounded
  network dependency at install only (nothing at runtime), and a minor privacy
  note (the installing machine's public IP reaches the geo endpoint). Recorded
  here so a future reader does not "fix" the lookup as stray telephone-home.
- The fallback keeps the installer fully functional offline — it simply lands on
  `Europe/Bucharest` when detection cannot run.
