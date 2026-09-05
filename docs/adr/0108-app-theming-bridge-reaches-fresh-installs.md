# App Theming Bridge reaches fresh installs; pure-compositor KColorScheme

---
Status: accepted. **Amends ADR 0102 and 0104** — both said "qt6ct.conf stays
**stowed**", but the installer **never stows** (ADR 0095): a fresh box seeds
`/etc/skel` and stows nothing unless a host sets `dotfiles_repo` (none does). So
the stow-only `qt6ct.conf` never reached a fresh install and every Qt/KDE app
rendered default white. **Also amends ADR 0104's fleet-wide `kcolorscheme`
drop** — re-enabled per-box on pure-compositor boxes. Root cause traced live in
the running `arch-combined` VM (Noctalia *was* generating
`qt6ct/colors/noctalia.conf`; only `qt6ct.conf` — the file that points qt6ct at
it — was missing), and the one-file fix was confirmed by before/after
screenshots (Dolphin white → themed).
---

The App Theming Bridge (ADR 0102) was **wired but undelivered**. Every other
piece shipped — `qt6ct-kde` + `adw-gtk-theme` installed, `QT_QPA_PLATFORMTHEME=
qt6ct` set per-compositor, `qt`/`gtk3`/`gtk4` templates enabled, GTK
`settings.ini` skel-seeded (ADR 0104) — but `qt6ct.conf`, the one file that sets
`custom_palette=true` and points at Noctalia's generated
`colors/noctalia.conf`, was classified "stowed" by ADR 0102/0104. A fresh box
seeds a curated *subset* into `/etc/skel` and does not stow, so `qt6ct.conf`
arrived on **no** freshly-installed machine (VM or real hardware); qt6ct then ran
with `custom_palette=false` and rendered Fusion's default light palette. The
bridge only ever completed on a box where the operator had manually cloned and
stowed the dotfiles.

## Decision

1. **Seed `qt6ct.conf` into `/etc/skel`**, beside the GTK `settings.ini` it was
   always meant to sit with. `noctalia-preset.sh` seeds it from the curated dir;
   `chroot.sh` stages `.config/qt6ct/qt6ct.conf` into both the niri and Hyprland
   curated dirs (explicit allow-lists, mirroring `config.toml`/pcmanfm-qt). It
   stays an ordinary stowable dotfile in the repo for the operator's own machine
   — this only adds the missing seed leg. `qt6ct.conf` is **compositor-private**
   (Plasma uses `plasma-integration` and never reads it), so seeding it fleet-
   wide is safe on a combined box (ADR 0104).

2. **Seed a boot-race snapshot** of the palette's Qt scheme to
   `/etc/skel/.config/qt6ct/colors/noctalia.conf`. `qt6ct.conf` targets a file
   Noctalia only writes once its daemon first applies; a Qt app launched in the
   sub-second before that would still be white. The snapshot is **seed-only**
   (never a stowed repo file — a stow symlink would push Noctalia's rewrite into
   the repo, the ADR 0104 dirt problem) and Noctalia **overwrites it on first
   apply**, so it self-heals. Belt against a slow/non-applying daemon; update it
   alongside the default palette.

3. **Re-enable `kcolorscheme` per-box on pure-compositor boxes.** ADR 0104
   dropped it fleet-wide because its `kde-color-scheme` post-action merges into
   the shared `~/.config/kdeglobals`, repainting the next Plasma session on a
   combined box. On a **pure** compositor there is no Plasma session to protect,
   so the merge is safe and gives KDE-framework apps (Dolphin/Gwenview/Kate) the
   **full** KColorScheme palette instead of only qt6ct's base QPalette. The
   preset injects `"kcolorscheme"` into the **seeded** `config.toml`'s
   `builtin_ids` only when `ENVIRONMENT_DESKTOP` (passed into the chroot) does
   **not** contain `kde`. The shared committed `config.toml` still ships without
   it (combined-safe default).

## Considered options

- **Fetch-and-stow at install** (set a `dotfiles_repo` default so the Runner
  stows) — rejected: ADR 0095 already ruled the installer cloning/stowing a
  user's dotfiles is the wrong seam; skel-seeding is the shipped delivery model.
- **Drop the boot-race snapshot** — genuinely marginal (the flash is sub-second
  and unobserved; the white we *saw* was the missing `qt6ct.conf`, not a race).
  Kept as a cheap, self-healing belt at the operator's request; it is the only
  static color file reintroduced since ADR 0102 and is clearly labelled.
- **Keep `kcolorscheme` off everywhere** (0104 as-is) — rejected: leaves
  Dolphin at base-palette-only even on a pure box where full fidelity is free
  and safe. The stated goal is a fully-themed KDE app under a compositor.
- **`kcolorscheme` on everywhere with per-session `XDG_CONFIG_HOME`** to isolate
  `kdeglobals` on combined boxes too — rejected as heavyweight (ADR 0104's
  finding stands); reserved for a future hard KColorScheme-fidelity need.
- **Two committed `config.toml` variants** (pure vs combined) — rejected: two
  authored sources of one file, the exact drift ADR 0095 warns against. The
  preset edits the seeded copy instead.

## Consequences

- **Qt/KDE apps follow the palette on every fresh install**, both compositors,
  all box classes — the bug is fixed at the delivery seam, not papered over.
- **On a combined box**, KDE apps under a compositor now get Noctalia's full
  base palette via the seeded `qt6ct.conf` (dark/light following via the portal
  chain, ADR 0104 amendment notes), losing only extended KColorScheme *accent*
  roles — the narrow cost ADR 0104 already accepted. **On a pure box** they get
  the full KColorScheme palette.
- **`config.toml` is byte-identical only *per box class*** now — the one narrow
  break from ADR 0097's byte-identical rule, confined to the seeded copy (the
  committed source is unchanged, one authored file).
- The drift-guard suite (`noctalia-stow.bats`) gains assertions that the preset
  seeds `qt6ct.conf` (staged on both adapters), the boot-race snapshot, and the
  conditional `kcolorscheme` injection.
- **Changing the default palette** now touches three places: `config.toml`'s
  selector, the seeded palette JSON (ADR 0109), and the boot-race snapshot.
