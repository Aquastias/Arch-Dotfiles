# 01 — Migrate plugin seeding to the v5 mechanism

**What to build:** The niri adapter seeds a Noctalia plugin the way v5 actually
loads it: the plugin's folder (`plugin.toml` + `.luau`) is vendored, at a pinned
ref, into skel `.local/share/noctalia/plugins/<dir>/`, and its canonical id
(`<author>/<plugin>`) is written into `[plugins].enabled` in skel
`.config/noctalia/config.toml`, with `[plugins].auto_update = "none"` and no
`settings.toml` shipped. Enabling is a single bool per plugin in
`install-niri.jsonc`. Proven by re-pointing the existing **Bitwarden**
plugin onto this path so it loads on a v5 Noctalia — which it does not today (it
still seeds the dead `plugins.json` + `.config/noctalia/plugins/` layout). The
old v4 seeding path is removed.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] A generic helper vendors a plugin folder at a pinned ref into skel
      `.local/share/noctalia/plugins/` and enables its id in `config.toml`.
- [ ] `config.toml` carries `[plugins].auto_update = "none"`; no `settings.toml`
      is written into skel.
- [ ] Bitwarden is seeded via the new path; the v4 `plugins.json` and
      `.config/noctalia/plugins/bitwarden/` artifacts are no longer produced.
- [ ] An offline/failed fetch skips that plugin with a warning; the install
      still succeeds.
- [ ] `niri-adapter.bats` asserts the new on-disk layout and the absence of the
      v4 artifacts.
