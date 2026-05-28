# Trim kde.sh shell block; relocate extra-cmake-modules; drop extra field; ADR 0021

Status: ready-for-agent

## Parent

`.scratch/package-list-categorization/PRD.md`

## What to build

Refactor the KDE Desktop Environment Adapter so it installs only
Plasma-required packages in its shell phase, and drops responsibility
for packages that don't belong to KDE.

Changes to `kde.sh`:

- Shell phase installs exactly: `plasma-meta`, `plasma-workspace`,
  `polkit-kde-agent`, `sddm`, `print-manager`.
- Remove `cups`, `extra-cmake-modules`, `sddm-kcm`,
  `xdg-desktop-portal-kde`, `kimageformats5` from the shell-phase
  pacman invocation.
- Remove the `paccache` post-shell branch's reliance on packages no
  longer installed here.
- Remove the `systemctl enable cups` line (now handled by the cups
  System Program from issue 02).
- Remove the `extra: []` traversal block — that field is being removed.

Changes to `install-kde.jsonc`:

- Remove the `extra: []` field entirely.
- Add `sddm-kcm: true`, `xdg-desktop-portal-kde: true`,
  `kimageformats5: true` as top-level entries inside `apps_list`
  (still flat at this stage — issue 05 reshapes to categorized).

Changes to `hosts/core/config.jsonc`:

- Add `extra-cmake-modules` to `packages.repo` (still flat array form
  at this stage).

New ADR:

- `docs/adr/0021-de-adapter-owns-de-packages.md` — captures the
  ownership boundary: Host Configs declare nothing that is derivable
  from `environment.desktop`; the DE adapter owns every package
  semantically tied to that DE.

## Acceptance criteria

- [ ] `kde.sh` shell phase installs only `plasma-meta`,
      `plasma-workspace`, `polkit-kde-agent`, `sddm`, `print-manager`.
- [ ] `kde.sh` no longer references `cups`, `extra-cmake-modules`,
      `systemctl enable cups`, or the `extra:` field.
- [ ] `install-kde.jsonc` no longer has an `extra` field.
- [ ] `install-kde.jsonc:apps_list` gains `sddm-kcm: true`,
      `xdg-desktop-portal-kde: true`, `kimageformats5: true`.
- [ ] `hosts/core/config.jsonc:packages.repo` contains
      `extra-cmake-modules`.
- [ ] A fresh install on `hosts/desktop` with
      `environment.desktop=kde` results in the same installed package
      set as before this change (cups via System Program;
      extra-cmake-modules via host core; sddm-kcm and others via
      apps_list).
- [ ] `docs/adr/0021-de-adapter-owns-de-packages.md` exists with
      Context, Decision, Consequences sections.

## Blocked by

- `.scratch/package-list-categorization/issues/01-migrate-kde-apps-to-adapter-config.md`
- `.scratch/package-list-categorization/issues/02-cups-system-program.md`
