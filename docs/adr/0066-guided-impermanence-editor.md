# Guided Installer: Impermanence Editor

The Guided Installer collapses the impermanence decision into one drill-down,
the way Encryption (ADR 0059) and Swap (ADR 0045) already do. The **Disks**
screen's inline `impermanence:` toggle and its separate `Add persist directory`
action row are replaced by a single **`Impermanence ▸ on/off`** row (carrying
the standard override `●` dot) that opens an **Impermanence Editor** screen
holding the enablement toggle *and* persist-directory management together — so
the two settings that were oddly split now live in one section.

Modelled on the Encryption/Swap sub-editors, the editor **collapses when off**:
it shows only `enabled: off`. When on it shows `enabled: on` (Enter toggles,
strict-delta — landing on the baseline drops the override), one row per
**user-added persist directory** (Enter removes it, direct — like sysctl / data
pools), a read-only summary line `curated defaults: N paths always persisted`
(not enumerated, mirroring the Packages screen's `derived … (read-only)` line),
and an `Add persist directory` action that appends to `persist.directories` and
returns to the editor.

Scope is deliberately narrow. **Directories only** — `persist.files` stays
file-editable (rare, and a path can't be classified dir-vs-file at config time
before it exists; validation stats it at install). The advanced
`options.impermanence.dataset` / `mount` fields stay **out** of the menu — safe
derived defaults, an install-time same-pool rule, and ZFS-only meaning (btrfs
ignores them, ADR 0044). Persist directories already in Config State are
**retained, not purged, when impermanence is toggled off** — just hidden until
re-enabled — exactly as Encryption keeps a stored passphrase; the existing
install-time warning ("persist declared but impermanence disabled") still covers
the mismatch.

This is a **menu-surface change only**. The stored shape
(`options.impermanence.enabled`, `persist.directories[]`), install-time
validation, the hybrid-GPU ban (ADR 0060), and the rollback mechanics
(ADR 0008 / 0044) are untouched.

## Considered Options

### Shape
- **Drill-down Impermanence Editor** — chosen. Consistent with the Encryption
  and Swap collapses; gives persist a home and de-clutters the Disks screen.
- **Keep inline, just group visually** — rejected. Leaves the toggle and the
  persist action as two peer rows — the split this ADR exists to remove.

### Persist management
- **List + remove + add** — chosen. A managed list (like sysctl / SSH keys /
  data pools); an append-only "section" is the same oddness being fixed.
- **Add-only (relocated)** — rejected. Still no way to undo a mistaken entry
  without hand-editing the profile.

## Consequences

- New nav screen `impermanence` (`nav_to_impermanence`, `nav_back` → Disks), its
  render + enter-dispatch, and a pure `edit_remove_persist` mirroring
  `edit_append_persist`; the `__persist__` text return re-routes from the Disks
  category to the editor.
- Pure logic (toggle delta, add/remove persist, off-collapse render) is
  bats-covered; the live drill is exercised by the PTY smoke harness like the
  other editors.

## Status

accepted — extends ADR 0059 (collapsible editor pattern); menu surface for
ADR 0008 / 0044 impermanence
