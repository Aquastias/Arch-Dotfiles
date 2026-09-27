# 04 — Bitwarden plugin for the Noctalia preset

**What to build:** As the operator running the Noctalia preset, I get the
official Bitwarden vault search wired into the launcher, ready for me to
authenticate. The preset installs `bitwarden-cli` (the `bw` backend the plugin
requires — it does not work with `rbw`), fetches the official "Bitwarden Vault
Search" Luau plugin at a pinned ref by `git` sparse-checkout of just the
`bitwarden/` subfolder from `noctalia-dev/official-plugins` into
`/etc/skel/.config/noctalia/plugins/bitwarden/`, and registers it in skel's
`plugins.json`. The installer only installs + wires + enables — `bw login` is my
own first-boot step ("prepared" = ready-to-auth). An off-switch lives as the
`bitwarden` bool in `install-niri.jsonc`.

**Blocked by:** 03 — `niri_shell` + Noctalia work preset (the preset, skel
seeding, and `install-niri.jsonc` must exist).

**Status:** done

- [x] Under `niri_shell=noctalia` with `bitwarden: true`, the adapter installs
      `bitwarden-cli`, sparse-checks-out the plugin at a pinned ref into the skel
      plugins dir, and registers it in skel's `plugins.json`.
- [x] `install-niri.jsonc` gains `bitwarden: true`; flipping it to `false` skips
      the CLI, the fetch, and the registration.
- [x] Offline (or fetch failure) skips the plugin with a warning and the install
      still completes successfully.
- [x] The Package Resolver reports `bitwarden-cli` as part of the Noctalia preset
      derived set when the bool is on.
- [x] The niri adapter test covers: plugin files + `plugins.json` registration +
      `bitwarden-cli` when the bool is on; nothing when off; and the offline path
      skipping without failing.

## Comments

- 2026-09-27 doc sync: shipped in 554ee50, 7fd8b7c, 554abf2 (ADR 0090); default
  palette later changed by ADR 0101/0109.
