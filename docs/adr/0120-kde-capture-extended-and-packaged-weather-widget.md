# KDE capture set extended; weather via a coordinate widget from the repos

---
Status: accepted. **Extends ADR 0111** (KDE adapter seeds captured Plasma
settings verbatim). Adds five config files to the captured set, pins night light
to a fixed location, and replaces the stock weather plasmoid — which cannot
target the operator's town — with a **repo-packaged** coordinate widget. Non-
`.config` first-login state is split out to ADR 0121.
---

ADR 0111 captured a fixed list of `~/.config` files verbatim. Re-inspecting the
live `arch-combined` box against the vendored snapshot showed the operator's
newer setup lives in files **outside** that list — activities, power, default
apps, welcome-version, window rules — so a fresh install silently dropped them.
Two settings also needed more than a verbatim copy: night light had only
`Active=true` with no mode (KWin then defaults to Automatic, which needs geoclue
and silently does nothing — ADR 0121 context), and the stock
`org.kde.plasma.weather` plasmoid **cannot find Râmnicu Vâlcea** (its provider
city databases miss small towns and it takes no raw coordinates).

## Decision

**Extend the ADR 0111 captured set** with `kactivitymanagerdrc` (+
`kactivitymanagerd-statsrc`), `powerdevilrc`, `mimeapps.list`,
`plasma-welcomerc`, and `kwinrulesrc`, copied verbatim like the rest. This seeds
Activities (Default + Dev), the power profile, default applications (video →
VLC), and window rules from first login. `powermanagementprofilesrc` stays a
Plasma-6 migration stub — `powerdevilrc` is the real power config.

**Pin night light to Location mode** in the captured `kwinrc`: set
`NightColorMode=Location` with the operator's fixed coordinates (Râmnicu Vâlcea,
≈ 45.10 N, 24.37 E) so sunrise/sunset are computed offline and in the VM, with
no geoclue dependency (see ADR 0121 for why Automatic is not viable).

**Replace the stock weather plasmoid with `plasma-applets-weather-widget-3`**
(the official `extra` package — blackadderkate's weather-widget-2, Kotelnik
lineage). It takes **manual latitude/longitude/altitude** and reads the free,
key-less **met.no** provider, so Râmnicu Vâlcea resolves by coordinate (≈ 45.10
N, 24.37 E, alt ~240 m) where the stock widget's city search fails. Installed by
pacman — **no vendoring, no version pin** — and configured in the captured
`plasma-org.kde.plasma.desktop-appletsrc` in the **same panel slot** the stock
widget occupied.

Add `orca` (accessibility) and `vlc` to the KDE package lists; `haruna` stays
installed but VLC is the captured default for video via `mimeapps.list`.

## Considered options

- **Keep the stock weather widget at Sibiu** — acceptable fallback the operator
  offered, rejected because a packaged widget that resolves the actual town by
  coordinate exists.
- **Vendor a richer third-party plasmoid** (`pnedyalkov91/advanced-weather-
  widget` — Nominatim search, map picker, 11 providers) — rejected: it is not in
  AUR or the official repos, so it would enter the vendored surface with a
  version pin and maintenance/update burden (ADR 0109 pattern). The `extra`
  package resolves the town with none of that cost; the extra features are not
  worth the pin.
- **Merge the new settings key-by-key** instead of adding whole files — rejected
  for ADR 0111's reason: verbatim copy restores exactly and avoids drift.
- **Night light Automatic (geoclue)** — rejected in ADR 0121; unreliable
  post-MLS and dead in a VM.

## Consequences

- The seed is a point-in-time snapshot of `arch-combined` (ADR 0111's re-capture
  caveat now covers more files) — re-tweaking Plasma means re-capturing.
- The weather widget is a repo package, so it tracks system updates with no
  vendored copy to maintain; only its `appletsrc` configuration (provider +
  coordinates + panel slot) is captured.
- Pure/stock KDE (ADR 0112) still skips the whole look layer, widget included.
