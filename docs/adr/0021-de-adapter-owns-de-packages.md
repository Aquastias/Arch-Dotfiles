# ADR 0021: Desktop Environment Adapter owns all DE packages

## Status
Accepted.

## Context
Host configs and Desktop Environment Adapters both declared KDE
packages. `hosts/desktop/config.jsonc:packages.repo` listed twenty
KDE apps (ark, dolphin, kate, …) that were also declared as defaults
in `extras/desktop/kde/install-kde.jsonc:apps_list`. Two sources of
truth drifted: adding a KDE app required editing two files;
de-selecting one was impossible without rewriting `kde.sh`.

Worse, `kde.sh`'s shell phase installed packages that are not
KDE-ecosystem: `extra-cmake-modules` (a build-time dep used by other
non-KDE packages) and `cups` (the Linux print daemon, not Plasma).
Operators could not infer from `install-kde.jsonc` what the adapter
would actually install — half the list lived in shell-script
literals.

## Decision
The Desktop Environment Adapter owns every package semantically tied
to its DE. Host configs declare nothing that is derivable from
`environment.desktop`.

Concretely for KDE:

- `kde.sh` shell phase installs a hardcoded minimum non-negotiable
  for a working Plasma session: `plasma-meta`, `plasma-workspace`,
  `polkit-kde-agent`, `sddm`, `print-manager`.
- Everything else KDE-ecosystem (apps, Qt plugins, portal
  integrations) lives in `install-kde.jsonc:apps_list` as togglable
  defaults.
- Non-KDE packages previously installed by `kde.sh` move out:
  - `extra-cmake-modules` → Host Core `packages.repo` (pure build
    dep, no service).
  - `cups` → new System Program at `programs/office/cups/`, listed
    in Host Core `system_programs`. Service enablement now lives
    where service enablement actually lives, not as a side effect of
    selecting KDE.
- The `extra: []` field in `install-kde.jsonc` is removed — there is
  exactly one way to add a KDE package: `apps_list`.

The ownership boundary: "would selecting `kde` imply this?" If yes,
adapter. If no, host config.

## Considered alternatives
**Status quo — duplicate in host config and adapter.** Two lists
drift on every change. Operator cannot de-select an app without
rewriting shell.

**Move only the app list, keep the shell hardcoded as-is.** Leaves
`cups` and `extra-cmake-modules` mis-located in `kde.sh` — opinions
about printing and build deps leak into "what Plasma needs to boot".

**Move everything (including the Plasma minimal core) into
`apps_list`.** Operators could accidentally produce an un-bootable
Plasma install by toggling `plasma-meta` off. The hardcoded minimum
in `kde.sh` is a safety rail.

## Consequences
- `hosts/desktop/config.jsonc` no longer carries KDE applications.
  Selecting `environment.desktop=kde` pulls in the full canonical
  KDE app set automatically.
- Adding a KDE app: one edit to `install-kde.jsonc:apps_list`.
- De-selecting a KDE app: flip its boolean to `false` in
  `install-kde.jsonc:apps_list`. No shell edit required.
- `cups.service` is enabled on every host (not only KDE hosts).
  Printing now works under any DE without per-DE wiring.
- `extra-cmake-modules` is available on every host (was previously
  KDE-only). Cost is negligible; payoff is that any package depending
  on ECM at build/runtime no longer needs to declare a DE-specific
  rule.
- Sets the pattern for other DE adapters. The Hyprland adapter will
  follow the same rule once its `aur:` field lands (ADR 0022 / PR3
  scope).
