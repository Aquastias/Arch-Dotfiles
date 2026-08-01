# Re-add Hyprland as a Desktop Environment Adapter

---
Status: accepted. Supersedes ADR 0050 (Hyprland removal); keeps ADR 0005's
adapter pattern.
---

Hyprland returns as a selectable `environment.desktop` value
(`_VALID_DESKTOP=(kde hyprland)`) via a restored `extras/desktop/hyprland/`
adapter. Display-manager selection follows the **pre-removal rule**: greetd +
greetd-tuigreet (`tuigreet --cmd Hyprland`) when KDE is absent, SDDM when KDE is
co-installed. `kde.sh` is unchanged (it always enables SDDM); the misdiagnosed
`a5b429d` change that made greetd own the DM even alongside KDE is **not**
restored — the black screen that motivated it was the impermanence logind race,
not an SDDM handoff failure (see ADR 0061), and it only occurred on a hybrid GPU,
now forbidden under impermanence (see ADR 0060).

The adapter is **core-only**: `hyprland`, `xdg-desktop-portal-hyprland`,
`xdg-desktop-portal-gtk`, `polkit-kde-agent`, `wl-clipboard` — the minimum
non-negotiable for a working session (ADR 0021). All former companion toggles
(bars, launchers, terminal, lock/idle/wallpaper, screenshot, nwg-look) and the
`qt6ct-kde` AUR theming bridge are **dropped**; the operator brings those via
dotfiles. qt6ct in particular is theming, not session plumbing, and does nothing
under a Plasma session anyway.

Two hardware fixes ride along:

- A `/usr/local/share/wayland-sessions/hyprland.desktop` override with
  `Exec=Hyprland`, so the SDDM path launches the compositor directly instead of
  the crashing `start-hyprland` supervisor (`std::system_error: Resource
  deadlock avoided`). `/usr/local` wins the DM's session scan and survives
  package upgrades. The greetd path already launches `Hyprland` directly.
- The `AQ_DRM_DEVICES` aquamarine DRM-node pinning (a udev rule minting a
  stable, colon-free iGPU symlink + `AQ_DRM_DEVICES` in `/etc/environment`),
  re-derived from git history but **relocated into the adapter** and gated on the
  resolved `amd`+`nvidia` hybrid set (read from `install-state.json`'s `gpu`
  array, ADR 0053's seam). Without it aquamarine grabs the first DRM node
  (usually nvidia) → broken. This fixes ADR 0050's placement smell: the pin is
  Hyprland/aquamarine-specific and now lives with the adapter that needs it, not
  in DE-agnostic `environment.sh`. It reaches every session (SDDM and tuigreet)
  because `/etc/environment` is read by `pam_env` at login.

## Considered alternatives

- **Forbid Hyprland on hybrid GPUs** (mirror the impermanence ban) — rejected:
  the hybrid laptop is the main place Hyprland is wanted, and the re-derived
  aquamarine pin makes it work.
- **Restore the full companion set verbatim** — rejected: three default-on
  launchers plus a pinned terminal was accumulated cruft; dotfiles own those.

## Consequences

- The Tier-2 install matrix regains its Hyprland cells automatically — `desktop`
  is a menu-derived pairwise axis, so widening the enum and regenerating adds
  them (no hand-editing), the mirror image of ADR 0050's removal.
- The glossary entries **Display Manager** and **Desktop Environment Adapter**
  (and the note at CONTEXT.md ~line 1147) update: KDE is no longer the sole DE,
  and DM selection is again multi-valued.
