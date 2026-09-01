# 02 — Extract the shared Noctalia-preset module + shared toggle file

**What to build:** move the Noctalia work-preset logic out of the niri adapter
into one shared module both the niri and Hyprland adapters can source (base
package set, plugin dep install, plugin vendoring at the pinned ref,
curated-config seeding into `/etc/skel`, laptop gating, first-login enable
one-shot). Rename `install-niri.jsonc` to the shared `install-noctalia.jsonc`
and restructure it into shared-core plugin bools + a `niri` slice + an (unused
for now) `hyprland` slice; make the shared package map and the Package Resolver
read it. This is a prefactor — niri must install **identically** afterwards, just
via the shared code path.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] Preset logic lives in one shared module; the niri adapter sources it and
      passes its compositor tag, curated config file(s), and plugin slice.
- [ ] `install-noctalia.jsonc` replaces `install-niri.jsonc` with shared-core +
      `niri` slice + `hyprland` slice; the shared package map exposes both slices.
- [ ] The Package Resolver reads `install-noctalia.jsonc`; install and query
      cannot drift.
- [ ] `config.toml`'s `[plugins].enabled` is reduced to the **shared-core
      plugins only** — the `niri-*` slice ids are removed from it; niri still
      activates its slice via vendoring + the first-login one-shot (behaviour
      unchanged).
- [ ] The drift guard equates the vendored set to the config's shared-core
      enabled list **plus** the active slice from `install-noctalia.jsonc`
      (`noctalia-stow.bats` green).
- [ ] The module keeps the injectable seams (`*_SEED_ROOT`, `*_CURATED_DIR`,
      JSON override, battery glob) the adapter tests drive.
- [ ] niri installs the same packages, vendors the same plugins, and seeds the
      same files as before (`niri-adapter.bats` and `resolver.bats` green).
