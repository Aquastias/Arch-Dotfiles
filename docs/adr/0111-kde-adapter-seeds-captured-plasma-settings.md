# KDE adapter seeds captured Plasma settings, custom colours included

---
Status: accepted. **Extends ADR 0088** (KDE adapter seeds DE defaults) — the
hand-written Breeze-Dark heredocs for `kdeglobals` / `kcminputrc` / `konsolerc`
/ `dolphinrc` are replaced by verbatim captured files; 0088's non-look seeds
(Plasma Welcome off, Baloo on, SDDM theme, GTK cursor inherit) are retained.
**Supersedes, for the standalone KDE look, ADR 0104's "the Plasma session stays
pure Breeze Dark"** — the operator's custom colour scheme is now the KDE
default. 0104's combined-host isolation (kcolorscheme stays off) is
**unchanged**.
---

ADR 0088 seeds a *minimal* KDE default look — a few `kdeglobals` keys, a cursor,
first-run flags — hand-authored as heredocs in `kde.sh`. The operator instead
built a full Plasma setup on the `arch-combined` reference box (custom dark
colour scheme, four virtual desktops, kwin plugins + tiling, faster animations,
30-min lock, klipper history, panel widget layout, KFileDialog view, Meta+X
close) and wants a fresh install to come up already configured — not first-run.

konsave (the community Plasma-profile tool) proves the mechanism: it captures a
**curated fixed list** of config files and copies them back verbatim — no
parsing, no regeneration. Restoration is exact because the widget layout lives
whole in `plasma-org.kde.plasma.desktop-appletsrc`, the colour scheme's values
live inline in `kdeglobals`, and UUID-keyed state (virtual-desktop IDs, tiling)
is self-consistent within `kwinrc`, which is copied whole.

## Decision

**Vendor the operator's captured Plasma settings into the KDE adapter and seed
them verbatim into `/etc/skel`**, konsave-style. The captured set
(`~/.config/`):
`kdeglobals`, `kwinrc`, `plasmarc`, `plasmashellrc`,
`plasma-org.kde.plasma.desktop-appletsrc`, `kglobalshortcutsrc`, `kcminputrc`,
`klipperrc`, `kscreenlockerrc`, `ksmserverrc`, `dolphinrc`, `konsolerc`,
`plasma-localerc`. The custom colour scheme rides **inline in `kdeglobals`**
(`[Colors:*]` + `ColorSchemeHash`, no separate `.colors` file), so `kdeglobals`
alone carries it. `kglobalshortcutsrc` already carries the Meta+X close bind
(ADR 0113).

**Excluded** (deliberately, not overlooked): `kscreenrc` /
`kwinoutputconfig.json` — monitor/output is host-specific and autodetected
(ADR 0110); akonadi/PIM runtime state and caches.

The custom colour scheme becomes the standalone KDE default, superseding 0104's
Breeze-Dark-only stance. On a **combined** `kde`+compositor host the App Theming
Bridge's `kcolorscheme` template stays **off** exactly as 0104 requires, so
Noctalia never merges into `kdeglobals`: the Plasma session shows the custom
scheme, a KDE-framework app under the compositor keeps Noctalia's qt6ct palette.
The two do not fight — 0104's isolation is the reason this is safe.

**Widget-dependency audit (the operator's explicit ask): no gaps.** Every
default Plasma widget's backend is a hard dependency inside plasma-meta's tree —
`libksysguard`→`lm_sensors` (sensor widgets), `plasma-vault`→`gocryptfs`
(vault), plus `plasma-nm` / `bluedevil` / `plasma-pa` / `powerdevil` /
`kdeplasma-addons`, all required-by `plasma-meta`. Installing the shell already
pulls them, so **no package is added to the seed**.

## Considered options

- **Keep 0088's minimal heredocs, ignore the operator's setup** — rejected: the
  request is precisely to seed the built configuration.
- **Parse/merge settings key-by-key** instead of verbatim copy — rejected:
  konsave shows verbatim copy restores exactly and is far simpler; merging risks
  drift and the UUID self-consistency that whole-file copy preserves for free.
- **Ship the colours as a named `.colors` file** — moot: Plasma stored the
  active scheme inline in `kdeglobals` on the reference box; capturing that file
  is sufficient.
- **Add widget optional-deps to the seed** (`lm_sensors`, `gocryptfs`) —
  rejected as redundant: the audit proved them hard deps already pulled.

## Consequences

- A fresh KDE login lands on the operator's full setup, not first-run —
  colours, desktops, widgets, shortcuts, lock, klipper all present.
- The seed is **captured**, so it is a point-in-time snapshot of
  `arch-combined`; re-tweaking Plasma means re-capturing. Documented like the
  vendored Noctalia cache (ADR 0109) and plugin set (ADR 0093).
- The Package Resolver's KDE report is unchanged (no new packages); the audit
  finding is recorded, not enacted.
- Pure/stock KDE (ADR 0112) **skips this seed entirely** — it is the full-look
  layer, not the shell.
