# Noctalia natively owns lock, idle, and polkit; wlroots desktop completion

---
Status: accepted. **Amends ADR 0097** (Noctalia as the shared niri/Hyprland
shell) — extends its "Noctalia locks natively" finding to *idle* and *polkit*.
Extends ADR 0090 (niri adapter + preset), 0093 (enriched plugins), 0094/0095
(curated config as stow payload / skel seed), 0098 (Bibata cursor).
---

ADR 0097 made Noctalia the one shared shell, but the two wlroots presets were
**shell-complete and compositor-thin**: no idle automation (nothing auto-locks,
suspends, or blanks on inactivity), the packaged `polkit-kde-agent` was never
autostarted (so GUI privilege prompts silently failed), niri's `config.kdl`
carried no `input`/`layout`/`window-rules`, and Hyprland's `Super+E` pointed at
a `dolphin` the adapter never installs. The operator wants **both** presets to
be a finished daily driver, not just a themed compositor under a rich bar.

The key finding that shapes this ADR: **Noctalia v5+ provides a built-in
`ext-session-lock-v1` locker AND a built-in idle daemon** (`[idle.behavior.*]`
with `lock` / `screen_off` / `suspend`, plus `lock_before_suspend`), and ships
its **own polkit agent**. So most of the gap is an *unconfigured-config* gap,
not a *missing-tooling* gap — closable in the stowed `config.toml` with zero new
packages, identically on both compositors. That is maximally aligned with ADR
0097's "one shared shell; only the compositor differs."

## Decision

**Noctalia owns lock, idle, and polkit natively; only the compositor differs.**

1. **Lock + idle: Noctalia-native on both.** The curated `config.toml` enables
   Noctalia's built-in idle behaviors and lock — no `hyprlock`/`hypridle`, no
   reversal of ADR 0097's package removals. Idle policy (the curated default):
   lock-hint ~2.5 min → lock ~5 min → DPMS-off ~10 min; `lock_before_suspend`
   on; idle inhibited while fullscreen video / audio plays. **Auto-suspend is
   laptop-on-battery only** (reuse `install-noctalia.jsonc`'s `laptop: "auto"`
   battery gate) — desktops get lock + DPMS but never auto-suspend.

2. **Polkit: Noctalia's built-in agent, verified once and hardcoded.** The
   installer picks packages at install time and *cannot* runtime-test whether
   Noctalia's agent works per box, so this is a **one-time design decision**,
   not a per-install branch, and **two agents never run at once** (double-
   prompt / race footgun). Verify Noctalia's agent at implementation time:
   - **If it works** → ship "Noctalia-native, no agent package" for everyone;
     the unconditional `polkit-kde-agent` install is **removed from both wlroots
     adapters** (`niri.sh` / `hyprland.sh`). The KDE adapter keeps its own
     `polkit-kde-agent` (KDE-only) unchanged.
   - **If it fails** → the shipped design is a KDE-aware fallback ladder, keyed
     on the co-installed `environment.desktop` set (install-time knowledge):
     **KDE co-installed** (kde+niri / kde+hyprland / kde+niri+hyprland) → the
     wlroots sessions **reuse** the already-present `polkit-kde-agent`;
     **no KDE** → install + autostart `hyprpolkitagent` (official `extra` repo,
     standard polkit, no Hyprland-protocol dep — verified against source).

3. **File manager: `pcmanfm-qt`.** Ship it in the shared preset with a
   compact-view, tree+Places, double-click layout. "Open current folder in
   kitty" is wired three ways: `Terminal=kitty`, the native **F4**
   (Tools → Open Terminal), and a right-click **"Open in kitty here"** custom
   action. The `Super+E` bind is fixed on Hyprland and added to niri for parity.
   pcmanfm-qt inherits Rosé Pine automatically via Noctalia's Qt template
   (qt5ct/qt6ct color scheme) — no extra theming. The custom-action set is
   **trimmed to tool-present actions** (Open in kitty, Copy path, Edit as root,
   Duplicate); mount-ISO / Samba-share / hash are **dropped** so no `samba` /
   `fuseiso` is dragged into every install — added later, per-need.

4. **niri compositor tuning.** The curated `config.kdl` gains `input` (touchpad
   tap-to-click + natural-scroll, keyboard layout/repeat), a minimal `layout`,
   and `window-rules`. **`output` is deliberately omitted** — display scale/mode
   is host-specific, and the curated config's portability rule already keeps
   host-bound surfaces out (per ADR 0094). Hyprland already carries the
   equivalent `input` / `monitor` / look-and-feel blocks; no change there beyond
   the `Super+E` fix.

## Considered options

- **Reintroduce `hyprlock` + `hypridle` (reverse ADR 0097)** — rejected as the
  *default*: Noctalia v5 now does lock + idle natively, so external tooling is
  redundant and re-crosses the core-only line 0097 cleaned up. But **pre-
  documented as the Hyprland escape hatch** (below).
- **`lxqt-policykit` as the fallback agent** — considered (official repo,
  Qt-themed, agnostic); rejected in favor of the operator's KDE-aware ladder,
  which reuses what a box already has rather than adding a third agent family.
- **Belt-and-suspenders: always ship a fallback agent alongside Noctalia's** —
  rejected: two agents registering per session is a known double-prompt / race
  bug. One agent, decided once.
- **Preset C's full action set** (mount ISO / Samba / hash) — rejected: drags
  `samba` / `fuseiso` onto every install for a context-menu row, and those are
  the wrong home for a tiling-box file manager.
- **Add an `output` block to niri** — rejected: host-specific, violates the
  curated config's portability rule.

## Consequences

- **Known-bug exposure, accepted with an escape hatch.** Noctalia's idle has
  open upstream issues (a suspend-vs-lock race; keep-awake not always blocking
  DPMS-off), and ADR 0097 recorded a lock-then-suspend **crash** on some
  Hyprland versions — precisely the Noctalia lock now shipped there. Stance:
  **accept-and-revisit on niri** (external tools are buggier there anyway); on
  **Hyprland**, if the suspend-crash reproduces, flip *that compositor only* to
  `hyprlock` + `hypridle` (Hyprland's canonical, still-current pair) — a config
  swap, not a rewrite. Not built now.
- The `polkit-kde-agent` line in `niri.sh` / `hyprland.sh` core is removed on
  the verification-passes path; the Package Resolver's report for those adapters
  changes to match (no drift).
- The shared preset gains `pcmanfm-qt`; `install-noctalia.jsonc` / the resolver
  reflect it.
- The glossary's **Wayland Shell Companion** entry records that Noctalia owns
  lock, idle, and polkit natively.
