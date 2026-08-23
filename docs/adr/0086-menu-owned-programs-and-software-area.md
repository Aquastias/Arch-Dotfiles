# Menu-Owned Programs and the Software area redesign

The Guided Installer's **Packages** category conflated five surfaces on one
screen — `repo`, `aur`, `derived`, a `host_programs` picker, and a free-text
`＋Add` that silently reclassified typed names by kind. Two symptoms drove this
ADR: a registry Program whose install is already governed by a dedicated control
(e.g. `grub` by the Bootloader enum, `clamav` by Security→antivirus) still
appeared *again* in a Programs picker, and the `＋Add` route reclassified names
invisibly. The fix is **menu-only** (the stored slots `host_programs` /
`packages.repo` / `packages.aur` / user `programs` are unchanged — they map to
real install mechanisms): make the menu express them consistently.

We introduce the **[[Menu-Owned Program]]**: a registry Program whose install is
governed by a dedicated menu control (Bootloader enum, Security/Backup/Services
toggles, or secrets activation). Its control is its **sole home** — never
default-installed as a program, never listed in either Programs picker. This
**generalizes** the `*_owned_programs` filter ADR 0079/0080 already applied to
`cups` / `bluetooth` / `power-profiles-daemon` / `tuned` into one
`menu_owned_programs` union, adding `grub`, the Security set (`firewalld`,
`ufw`, `clamav`, `rkhunter`, `apparmor`), the Backup set (`borg`,
`zfs-auto-snapshot`),
and `sops`. Because **every `kind: host` program is Menu-Owned**, no
free-standing Host Program remains, so the **Packages** category lists **no
Programs at all**: its `host programs` row is dropped and it drills only
`repo` / `aur` / `derived`. The category **keeps the name `Packages`** — once
the Programs row is gone it is no longer a misnomer (it holds only packages), a
`Software` name would merely echo the `SOFTWARE` bucket header it already sits
under. The five free-standing User Programs (`docker`, `podman`, `virt-manager`,
`searxng`, `teamspeak3`) stay in their one home, the [[User Editor]] under
**Users**.

The `＋Add` magic is replaced by an explicit **guard**. On `repo`, `＋Add` opens
a package browser — `pacman -Slq | fzf --multi --preview 'pacman -Si {}'`, the
installer's own fzf surface reproducing archinstall's browser UX (filter +
info-preview + multi-select). Each picked name is routed visibly: a Menu-Owned
name **informs** ("managed by \<Control\>", not added), a free-standing user
program **offers** to add under Users, anything else lands in
`packages.<slot>.extra`. Control defaults are untouched — delisting a program
never changes whether it installs.

## Considered options

- **Delist Menu-Owned programs** (chosen) over **keep listing them** — a program
  that a control already owns has exactly one correct home; listing it twice is
  the duplication that reads as inconsistent, and produces an invalid config if
  added to the wrong slot.
- **Packages = host-declared only, user programs in Users** (chosen) over a
  **symmetric Host/User Programs split in Packages** — the guided menu's spine
  is already "Users category = per-user, everything else = host-declared"; a
  second User-Programs editor in Packages would recreate the two-homes drift
  this ADR removes. It also makes the empty Host side honest: nothing to show.
- **`＋Add` browser via fzf + pacman** (chosen) over **reusing archinstall's own
  selector** or **free-text only**. archinstall 3.0 (PR #3196) loads the full
  sync DB into its bespoke Python `archinstall.tui.curses_menu`; shelling into
  Python internals is not viable for a bash installer and a heavy dep for one
  screen, whereas `pacman -Slq | fzf --preview 'pacman -Si {}'` gives the same
  UX on the surface the installer already standardises on. AUR is not in the
  sync DB (and paru is not yet bootstrapped at menu time), so the `aur` slot
  stays free-text — repo-only, matching archinstall's own scope.
- **Menu-only, keep the schema** (chosen) over **collapsing the slots** — the
  slots encode genuinely different install mechanisms (root/pacstrap vs per-user
  paru vs chroot Host Program); collapsing them is a large, riskier back-end
  change and the confusion lives in presentation, not storage.

## Consequences

- The `host_programs` picker is now always empty and the **Packages** category
  has no Programs child. A future free-standing `kind: host` program (not owned
  by any control) reintroduces the section — the filter, not a special case,
  decides.
- The guard preserves the config-load exclusivity invariant (a Program name may
  never sit in `packages.*`, which aborts at load) while making every
  reclassification explicit and consented — the old emit-path/entry-path magic
  is gone.
- The `repo` `＋Add` browser needs a synced pacman DB (`pacman -Sy`) or the list
  is empty, the same operational gotcha archinstall hit (issue #3307).
- Extends, does not supersede, ADR 0079/0080: those delisted three service
  programs; this folds them and ten more into one `menu_owned_programs` set.
- The redundant top-level **extra packages** row was removed: `repo` `＋Add`
  browses and `aur` `＋Add` types, both writing `packages.<slot>.extra`, so a
  third free-text path made no sense. The Packages category is now a pure
  repo/aur/derived drill with no field rows; its ● folds from the package
  override map instead of that row.
- **Category renames to stop bucket-header echoes:** any category whose name
  repeated its bucket was renamed — **Services → Daemons**, **Advanced →
  Expert** — and the `SYSTEM` bucket → **`GENERAL`** (keeping the `System`
  category, so ADR 0081's identity-anchor rename stands). `SECURITY & DATA` /
  `Security` is left as a partial, non-exact overlap.
- Design validated against a throwaway TUI prototype at
  `.scratch/software-menu-redesign/prototype-tui.html`.

## Amendment (2026-08-23): in-place browser, not a nested fzf

The `repo` `＋Add` browser first shipped as an fzf `execute()` hand-off: the
persistent fzf suspended, `pacman -Slq | fzf --multi --preview 'pacman -Si {}'`
ran as a second process on the tty, then the menu reloaded. The teardown between
the two processes flashed the bare terminal for a fraction of a second — jarring,
and the residual could not be masked (paint in the gap races the parent's own
teardown).

Reworked to browse **in place**: a new `pkgbrowse` nav screen renders the whole
`pacman -Slq` universe as toggle rows in the *same* persistent fzf. No second
process, no screen teardown, no flash. `Enter` toggles a package (add routes
through the same `_ctl_route_package_entry` guard; remove drops a session-added
extra or excludes an inherited core package), replacing `TAB` multi-select — the
toggle-in-place model the rest of the menu already uses. The preview pane keeps
`pacman -Si {}`. The package list is prewarmed into a tmpfs cache at menu launch
(`GUIDED_PKGLIST_FILE`) so the screen opens instantly; an empty cache falls back
to a live `pacman -Slq`, preserving the synced-DB gotcha above.

Rows also flag provenance from the same three-state map the per-category screen
uses: `●` for a session/profile-touched package, and `⟲ derived` for one the
Package Resolver already pulls in (base set, kernel, DE, fonts, login shell, …).
A derived row is read-only here — Enter says where its source lives (ADR 0021)
rather than duplicating it into `extra`. Resolving the derived set is the
render's expensive step and is invariant while only extras are toggled, so it is
cached (`GUIDED_PKGDERIV_FILE`) keyed by the config with the browse-add buckets
stripped: an add hits the cache, a derivation change (GPU/DE/kernel/…) recomputes.

## Amendment (2026-08-23): AUR browses in-place too

This ADR originally kept `aur` `＋Add` as free-text because AUR is not in the sync
DB and no helper is bootstrapped at menu time. The in-place browser makes parity
worth the reversal: `aur` `＋Add` now opens the *same* `pkgbrowse` screen as repo
(`slot=aur`), sharing the marking, toggle, derived-flagging and caching logic.

Only the network-touching seams differ, because AUR has no local data:

- **Enumeration** comes from the published `packages.gz` (all AUR names), not a
  local DB. Fetched **lazily** on first open (a network call, so unlike the
  repo `pacman -Slq` prewarm it must not run on every launch), gunzipped, and
  session-cached in `GUIDED_AURLIST_FILE`. `curl` is bounded (`--connect-timeout
  2 --max-time 8`) so offline never hangs the menu.
- **Preview** is the AUR RPC `info` endpoint (description, version, maintainer,
  votes, out-of-date), one bounded call per hovered package cached under
  `GUIDED_AURINFO_DIR`; only a good fetch is cached, so a timeout retries.
- **Query-as-add** stays: a typed name that matches no row still adds to
  `aur.extra` (via the guard). It is the offline path (type into an empty list)
  and reaches brand-new packages the fetched list lags. Repo keeps no query-add
  — it is fully enumerable, so an unmatched repo name is a typo, not a package.

Offline, the screen is entered uniformly (empty list + a type-to-add notice)
rather than diverging to a second screen. Network at menu time is a new but
acceptable dependency: the install already needs it (AUR builds git-clone from
`aur.archlinux.org` and hit `/rpc`), and it degrades to the old free-text
behaviour when it is absent. Nothing persists — the caches are tmpfs, reaped on
menu return, and `/root` is RAM on the live ISO.
