# 02 — Adapter `plugins` section (per-app optdepends)

**What to build:** The chosen KDE apps become capability-complete out of
the box. The KDE adapter config gains a `plugins` section — the same
2-level Categorized-List shape, keyed by app — declaring each app's
optional-dependency enhancers: Dolphin (`dolphin-plugins`, `kio-admin`,
`kdegraphics-thumbnailers`, `ffmpegthumbs`, `kimageformats`,
`kdegraphics-mobipocket`, `kde-cli-tools`), Ark (`7zip`, `unrar`),
Okular (`ebook-tools`), Gwenview (`qt6-imageformats`), Krita
(`krita-plugin-gmic`), Kdenlive (`opencv`, `noise-suppression-for-voice`,
`recordmydesktop`), digiKam (`darktable`), KDE Connect (`sshfs`). The
adapter installs the section in the same pacman pass (`--needed` dedups
packages shared across apps); the Package Resolver reports it; every
plugin is deselectable in the Guided Installer.

**Blocked by:** 01 — reuses the section-install path and resolver
pattern established there, and edits the same adapter files.

**Status:** ready-for-agent

- [ ] `plugins` is a sibling Categorized-List section keyed by app,
      parsed in bool mode
- [ ] The adapter installs selected plugins; deselected (`false`) leaves
      are not installed; a malformed section aborts with a pathed parser
      error
- [ ] The Package Resolver emits `kde-plugins` (layer `derived`,
      category `Environment`)
- [ ] `kde-adapter.bats` covers select / deselect / malformed for
      `plugins` plus a membership lock on the shipped section
- [ ] All plugin packages resolve to the `extra` repo — no new AUR in
      the adapter
