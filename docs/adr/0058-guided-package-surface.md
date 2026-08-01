# Guided package surface: Host Core baseline, provenance, derived section

---
Status: accepted
---

The Guided Installer's menu **loads Host Core as its baseline** instead of
hand-copying a subset of it, gains a **Packages screen** with three-state
provenance marking and a **read-only `derived` section**, and the
front-end-specific **promotion rule is deleted** in favour of a config-load
abort.

The invariant this establishes: **the same file produces the same install
through every front-end.**

## Host Core as the baseline

`cfgstate_seed_defaults` hand-copied a handful of Host Core's values
(swappiness, and nothing else) rather than loading Host Core. Consequences:

- `cups` installs on every host and appeared **nowhere** in the menu.
- `packages.repo` and `packages.aur` had **no menu representation at all**, so
  seeding a profile silently carried its whole package payload into Config
  State where the operator could neither see nor deselect it.

The baseline is now `layer_resolve(HostCore, computed_defaults)` (ADR 0057).
Core's contents surface as **seeded-but-unmarked** rows: present and checked,
with no override dot, because the operator has not touched them.

Host Core therefore enters the pipeline **exactly once**. The emitter no longer
merges it a second time — that double-merge, combined with the view's replace
semantics, is precisely what made the menu show `system programs: grub` while
the install produced `["cups", "grub"]`.

This is the fix for the original report — *"if I choose a profile containing
system level programs, these do not appear selected in the menu."* The root
cause turned out to be the inverse of the symptom: profile programs **do** mark
correctly; it is **core** programs that were invisible, and the merge that
under-reported.

## Packages screen

Drills `repo` → category → package toggles, mirroring the Categorized List
shape the JSONC already uses, so the screen matches the file. `aur` drills the
same way. Categories keep each list short enough to read and carry a count.

Three states, reusing the existing override dot rather than inventing glyphs:

| render | meaning |
|---|---|
| checked, no dot | inherited from Host Core |
| checked, with dot | added by this profile or session |
| unchecked, with dot | excluded by this profile |

Unchecking an **inherited** package writes a `packages.exclude` entry — that is
what makes the exclusion mechanism reachable from the menu at all. Unchecking a
package this session added simply drops it from the override; re-checking an
excluded package removes the exclusion.

One constraint: the toggle list can only offer the **declared union** across
Host Core and the profile. The universe of Arch packages is not enumerable, so
adding a brand-new package stays a free-text entry.

## Read-only `derived` section

Even with the declared packages editable, a large set arrives without appearing
anywhere: the Plasma shell, KDE applications and the adapter's AUR list, GPU
drivers, the auto-derived audio stack, the Security and Backup Extras, and
`sops` when secrets are present.

The `derived` section lists these grouped by source, each naming the category
that drives it, so the operator knows where to go to change it. It calls the
**same Package Resolver** as the `explain-packages` CLI inspector, so the two
cannot drift.

Deliberately **not toggleable**: ADR 0021 gives the DE adapter ownership of its
own package set, and these are consequences of choices already made elsewhere
in the menu.

## Promotion deleted

A typed package name resolving to a Program used to be promoted into
`system_programs` — but **only in the Guided Installer's emit path**.
`install.sh --profile` and `install.sh <config-file>` never promoted, so a
hand-edited profile and a TUI-authored one were not equivalent.

A name is now **either a Program or a package, never both**, enforced at config
load: any `packages.repo` or `packages.aur` entry resolving to a program
directory aborts, naming the offending path and the correct slot. With that in
place, promotion has nothing left to do.

The guided convenience is preserved by moving resolution to **entry time**:
typing a Program name into the extra-packages row reports it and routes it to
the right slot before anything is stored. What lands in Config State is always
canonical, so Save, Export and Proceed all agree.

Three live violations were removed for the committed profiles to keep loading:
`docker` and `virt-manager` (declared as repo packages *and* as user Programs
on both hosts) and `teamspeak3` (declared as a repo package despite being
AUR-only — pacstrap would have failed on it).

## Program pickers obey the `system` flag

One unfiltered function fed two screens with **opposite** requirements: the
host System Programs picker needs `system: true` (3 of 15 qualify), the User
Editor's picker needs `system: false` (12 of 15). Each offered all fifteen, so
the host side could build a config that fails validation at Proceed, after the
operator had done all their other work.

The program registry now carries the `system` flag and exposes one kind lookup
(`system` / `user` / `none`), built once per run. Both pickers filter on it.

Tests assert the **membership** of each picker's option set, not only the
`[x]`/`[ ]` marking — marking-only assertions are what let this through.

## Consequences

- Everything Host Core installs is visible and deselectable in the menu.
- Save Profile writes a delta over Host Core, so a saved profile stays layered
  rather than freezing a snapshot.
- The menu's effective view and the emitted Effective Config are one
  computation, not two that happen to agree.
