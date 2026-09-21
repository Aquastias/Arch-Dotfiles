# KDE per-activity Kickoff favorites reconstructed at first login

---
Status: accepted. **Complements ADR 0121** (First-Login State) and **extends ADR
0120** (which seeds the Default + Dev Activities but not their favorites). The
Kickoff launcher's favorites are the one remaining piece of the "looks like
`arch-combined`" guarantee that has no capturable per-user `.config` file, so it
joins the reconstructed set.
---

ADR 0111/0120 seed the operator's Plasma look by copying `~/.config` verbatim,
including `kactivitymanagerdrc` (the Default + Dev Activities) and the Kickoff
applet in `plasma-org.kde.plasma.desktop-appletsrc`. But a fresh login showed an
**empty Favorites grid**. VM investigation (arch-combined) established why:

- In Plasma 6, Kickoff favorites are **KActivities-linked resources**. Link
  membership lives in a **SQLite DB**,
  `~/.local/share/kactivitymanagerd/resources/database`, table `ResourceLink`
  `(usedActivity, initiatingAgent, targettedResource)` — **not** a `.config`
  file. That DB is under `~/.local/share`, outside the captured set, so it is
  never seeded and `ResourceLink` starts empty.
- The two captured `.config` half-pieces cannot substitute. The appletsrc inline
  `favorites=` + `favoritesPortedToKAstats=false` is only a legacy one-shot
  import; on the box it flipped to `true` with `ResourceLink` still empty, so it
  is unreliable. `kactivitymanagerd-statsrc` `[Favorites-…-<uuid>] ordering=`
  only **sorts** resources already linked — it establishes no membership.
- The link is host-agnostic: a `ResourceLink` row references only the Activity
  UUID (or `:global`), the agent `org.kde.plasma.favorites.applications`, and an
  `applications:<id>.desktop` resource — no machine/device id.

## Decision

**Reconstruct the favorites at first login** (the ADR 0121 pattern), not by
copying the DB. The KDE adapter seeds a fixed-path helper
`/usr/local/bin/kde-seed-favorites` and a KDE-only, run-once autostart. The
helper waits for the Activity Manager, then calls
`LinkResourceToActivity(org.kde.plasma.favorites.applications,
applications:<id>.desktop, <activity>)` once per (Activity, app) pair — the exact
DBus call the "Add to Favorites" menu makes — and stamps
`~/.local/state/kde-favorites-seeded` so it never re-runs. The pinned set
(all VM-verified installed on any non-stock KDE host):

- **Both** (`:global`): dolphin, zen, konsole, discord, teamspeak3, virt-manager
- **Default** (`061c…`): steam, bolt-launcher, octopi, discover, sweeper,
  krename, kfind
- **Dev** (`d71c…`): codium, kommit, neovide, kate, kitty

To keep the reconstruction authoritative, the vendored appletsrc is set to
`favoritesPortedToKAstats=true` (so Kickoff never runs the legacy import that
would race the helper) with the inline `favorites=` reduced to the `:global`
set, and `kactivitymanagerd-statsrc` `ordering=` is rewritten to the pinned
order (`:global` apps first, then the Activity's own).

**Scope: every non-stock KDE host**, alongside the captured settings that back
it — the Activities and the apps already land there (ADR 0120 + Host Core
userland), and linking a missing `.desktop` is a harmless dead row, so a narrower
scope would only be an inconsistency. Pure/stock KDE (ADR 0112) skips the whole
skel seed and so skips this too.

## Considered options

- **Seed the SQLite DB verbatim** into `/etc/skel/.local/share/…/database`
  (konsave-style, extend ADR 0111 to `.local`) — rejected: binary blob with
  `-wal`/`-shm` sidecars and a schema version `kactivitymanagerd` may migrate or
  rewrite; fragile where a declarative relink is not.
- **Rely on the inline `favorites=` legacy import** — rejected: global-only (no
  per-activity split) and empirically did not populate `ResourceLink` on the box.
- **Capture only `ordering=`** — moot: it sorts, it does not link.

## Consequences

- Favorites are **reconstructed**, joining audio volume et al. as First-Login
  State (ADR 0121) — not present in the captured skel set; a future reader must
  not expect a favorites `.config` file.
- The pinned list is hand-maintained in the adapter, not captured. Re-capturing
  Plasma does not update it; changing favorites means editing the helper.
- A re-capture of `plasma-org.kde.plasma.desktop-appletsrc` /
  `kactivitymanagerd-statsrc` will reintroduce the stale `favorites=` /
  `favoritesPortedToKAstats=false` / `ordering=` — the three overrides above must
  be re-applied after any re-capture.
- The helper is `OnlyShowIn=KDE`, so on a shared-$HOME combined box that mostly
  runs niri/Hyprland it only fires on the **first Plasma login** — until then
  Kickoff shows no favorites, which is expected, not a regression.
- Reliability (VM-observed): the helper now stamps **only after
  `kactivitymanagerd` answers** (`ListActivities`), waiting up to 60 s; if the
  manager never comes up it exits **without** stamping so the next login retries.
  The earlier version stamped unconditionally, so a first-login race could mark a
  no-op done and leave the Favorites grid permanently empty.
- The grid is empty for the ~second between login and the helper linking; it then
  populates live via the `ResourceLinkedToActivity` signal. No re-login needed.
