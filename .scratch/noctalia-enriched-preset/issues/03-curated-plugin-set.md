# 03 — Wire the curated plugin set

**What to build:** A fresh niri+noctalia session comes up with the full curated,
overlap-free plugin set installed and enabled: `keymap`,
`niri-active-workspace`, `niri-animations`, `niri-displays`, `sharednd`,
`screen-toolkit`, `wl-screen-mirror`, `arch-updater`, `audio-switcher`,
`procmon`, `cat`, `gamer-mode`, `drive-health`, `eyecare`, `file-search`,
`shell-command`, `ssh-launcher`, `mini-docker`, `custom-shortcut`, `udiskie`,
`todo`, `wallpaper-switcher` (plus Bitwarden from ticket 01). Each runs through
the bool-driven loop, is vendored at a pinned ref from the two source repos, has
its `install-niri.jsonc` bool, and pulls its wrapped system-tool dependency
(e.g. wl-mirror, smartctl, docker, fzf) only when enabled. The Package Resolver
reports the enriched preset set. The dropped plugins (`keybind-cheatsheet`,
`color_picker`, `screen_recorder`, `battery-threshold`, `config-swap`,
`calculator`, `system-monitor`, `system-updater`) stay absent. Turning every
plugin bool off recovers the lean shell.

**Blocked by:** 01.

**Status:** done

- [x] All curated plugins seed + enable via the ticket-01 loop; each has an
      `install-niri.jsonc` bool (default on).
- [x] Each plugin's system-tool dependency installs only when its bool is on;
      dropped plugins install nothing.
- [x] The two source repos are pinned to one ref each; bumping is two SHAs.
- [x] The Package Resolver reports the enriched Noctalia preset set per
      `install-niri.jsonc`.
- [x] Turning all plugin bools off reduces to the lean shell (+ palette).
- [x] `niri-adapter.bats` and `resolver.bats` assert the enabled set, the
      per-bool gating, and the absence of dropped plugins.

## Comments

- 2026-09-27 audit: 06ab093, a30056f (niri-adapter.bats, resolver.bats). Later:
  bitwarden/mini-docker dropped (ADR 0094); set now in install-noctalia.jsonc
  (ADR 0097).
