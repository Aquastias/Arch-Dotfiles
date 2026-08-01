# Guided Packages screen

Status: done

## Parent

.scratch/layered-software-model/PRD.md
ADR: 0058 (to be written)

## What to build

Make the package set editable in the menu, and make provenance visible.

`packages.repo` and `packages.aur` have no menu representation at all today.
Seeding a profile silently carries its whole package payload into Config State
where the operator can neither see nor deselect it.

Add a Packages drill-down mirroring the Categorized List shape the JSONC
already uses: `repo` → category → package toggles. Categories keep each list
short enough to read, and the screen matches the file.

Three states, reusing the existing override dot rather than inventing glyphs:

- checked, no dot — inherited from Host Core
- checked, with dot — added by this profile or session
- unchecked, with dot — excluded by this profile

Unchecking an inherited package writes an `exclude` entry into Config State.
That is what makes the exclusion mechanism reachable from the menu at all.

One constraint to respect: the toggle list can only offer the **declared union**
across Host Core and the profile. The universe of Arch packages is not
enumerable, so adding a brand-new package stays a free-text entry.

## Acceptance criteria

- [ ] Packages drills `repo` → category → package toggles
- [ ] `aur` drills the same way
- [ ] Each category row shows its package count
- [ ] An inherited package renders checked with no override dot
- [ ] A package added in this session renders checked with a dot
- [ ] Unchecking an inherited package writes an `exclude` entry
- [ ] An excluded package renders unchecked with a dot
- [ ] Re-checking an excluded package removes the exclusion
- [ ] The toggle list offers the declared union across core and profile
- [ ] A free-text entry adds a package not in the union
- [ ] Edits survive leaving and re-entering the screen
- [ ] Edits commit on confirm and not on Esc

## Blocked by

- Menu reads Host Core via the Layer Resolver
