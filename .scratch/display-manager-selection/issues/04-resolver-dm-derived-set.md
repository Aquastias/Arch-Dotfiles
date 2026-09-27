# 04 — Package Resolver reports the Display Manager derived set

**What to build:** The operator inspecting packages (via the explain-packages
tool and the Guided Installer's read-only `derived` section) sees the display
manager reported as its own derived set, keyed on the resolved
`display_manager`, so they can tell which greeter a config installs and why —
instead of `sddm` being smuggled inside the KDE-shell set where it looked
KDE-owned.

**Blocked by:** 01.

**Status:** done

- [x] The Package Resolver emits a `display-manager` derived set reporting the
      greeter package(s) for the resolved value: `sddm` for `sddm`, `greetd` +
      `greetd-tuigreet` for `greetd`, nothing for `none`.
- [x] `sddm` is removed from the KDE-shell derived set; `sddm-kcm` stays in the
      KDE set.
- [x] The resolver stays declarative — no pacman query, no network — and the
      set is deterministic headless.
- [x] The resolver bats cover the DM set for each resolved value and assert
      `sddm` no longer appears in the KDE-shell set.

## Comments

- 2026-09-27 audit: 0d89698 (resolver.bats display-manager source).
