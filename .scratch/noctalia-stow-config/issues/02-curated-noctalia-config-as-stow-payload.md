# 02 — Curated Noctalia config ships as stow payload with the corrected plugin set

**What to build:** a fresh niri+Noctalia install reproduces the operator's full
curated desktop (bar order, widget placement, dock, lockscreen, palette) on first
login — and that config lives outside `.installer/` as ordinary stowed dotfiles
the operator can edit and version. The niri adapter stops seeding config/scripts
to `/etc/skel` and only vendors plugins; the Runner's existing per-user
`stow --no-folding` step delivers the payload, so the config is shipped by the
installer AND independently `stow .`-able from a single source. The installed and
enabled plugin set is corrected to exactly the operator's curated list.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

Anchor: ADR 0094 (curated config as stow-owned dotfile; partial-supersede of
0093's widget-placement clause). Extends ADR 0090/0093/0012.

## Stow payload (new, repo-root top-level trees)

- [ ] `.config/noctalia/config.toml` — the full curated look:
      `[theme]` `source="builtin"`, `builtin="Rosé Pine"`, `mode="dark"`,
      `community_palette="Oxocarbon"`, `wallpaper_scheme="m3-content"`;
      `[shell] font_family="Noto Sans"` + `app_icon_colorize=true`;
      `[audio] enable_overdrive`; `[dock]`; `[nightlight]`;
      `[wallpaper.default] path="/usr/share/noctalia/assets/noctalia-wallpaper.png"`;
      `[plugins] auto_update="none"`, `enabled=[curated ids]`; the curated
      `[bar.*]`/`[widget.*]` and `[lockscreen_widgets]` widget-list blocks; the
      `[plugin_settings."yocraft/custom-shortcut"]` tile block.
- [ ] Host-bound / dead content is **absent** from `config.toml`: bing
      `[wallpaper.last]`/`[wallpaper.monitors.Virtual-1]`, the `@Virtual-1`
      lockscreen widget geometry block, the orphan widget stanzas
      (`icefish/phone-connect`, `3ri4ng0ld/ip-monitor`, `fel/ocr`), and the
      `[bar.default] font_family` override.
- [ ] `.config/niri/config.kdl` — glue: autostart `noctalia --daemon`, bind kitty
      + native screenshot, spawn the plugin-enable one-shot.
- [ ] `.local/bin/noctalia-cycle-palette` and `.local/bin/noctalia-enable-plugins`
      — the palette cycler and first-login one-shot, moved verbatim from the
      adapter heredocs, executable.

## Adapter slim-down + set correction

- [ ] `extras/desktop/niri/niri.sh` no longer seeds `config.kdl`, `config.toml`,
      the cycler, or the enabler to `/etc/skel`; it keeps core, session curation,
      preset packages, cava/cliphist toggles, plugin vendoring to
      `/etc/skel/.local/share/noctalia/plugins`, tool-dep install, laptop gating.
- [ ] All Bitwarden logic removed from the adapter (the `bitwarden` bool, the
      pinned-ref constants, the plugin section, the plain-`nodejs` →
      `nodejs-lts-jod` swap).
- [ ] `extras/desktop/niri/install-niri.jsonc` drops the `bitwarden` and
      `mini-docker` bools and adds bools for `portctl`, `game-launcher`,
      `hotspot`, `bookmarks`, `llamanager`, `dns-switcher`.
- [ ] `lib/packages/niri.sh`: `noctalia_community_plugins` updated to the curated
      set; `noctalia_bitwarden_packages` removed; `noctalia_plugin_deps` extended
      (`game-launcher`→`xdg-utils`, `hotspot`→`iw`, `llamanager`→`ollama`,
      `dns-switcher`→`bind`) and the `mini-docker`→`docker` case dropped.
- [ ] Laptop battery pair stays auto-gated and is not in the static `enabled`
      list (the one-shot enables it at login on battery hardware).

## Tests (the agreed seams)

- [ ] Seam A — `tests/extras/niri-adapter.bats` reshaped: drop every
      config/script **seed** assertion and all Bitwarden tests; keep the
      vendoring/packages/gating/lean-recovery tests; add vendoring of the six new
      plugins + their new deps; assert `bitwarden`, `mini-docker`, and
      `system-updater` are never vendored and `docker`/`bitwarden-cli` never
      installed.
- [ ] Seam B — new `tests/config/noctalia-stow.bats` over the committed payload:
      required keys/values present, forbidden host-bound/orphan content absent,
      scripts present + shaped, and the **drift guard** — the `config.toml`
      `enabled` list equals `noctalia_community_plugins` (sourced from
      `lib/packages/niri.sh`) minus the laptop pair.
- [ ] Bare niri (`niri_shell=none`) still seeds nothing — unchanged.
- [ ] The full installer test suite passes.
