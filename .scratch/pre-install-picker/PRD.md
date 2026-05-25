Status: done

# PRD: Pre-Install Picker

## Problem Statement

The installer is fully declarative — every input lives in
`install.jsonc` and the merged host/user configs. That is the point
(ADR-0002, ADR-0003) and it must stay that way.

Two facts cannot be known until the operator boots the live CD in
front of the target machine:

- which host config to apply (which sets the hostname)
- which `/dev/disk/by-id/*` device(s) to install onto

Today those are resolved by hand-editing `.os/install.jsonc` on the
live CD. The by-id paths are long, opaque, and machine-specific
(`/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_...`); they can't be
committed in the repo without binding `install.jsonc` to one physical
machine. Hand-editing the file on the live CD is the friction point.

Every other field — locale, timezone, keymap, bootloader,
`environment.desktop`, `environment.gpu`, `options.encryption`,
`options.impermanence.*`, ZFS pool/dataset names, `options.age_key_url`
— is a property of the machine, not of any particular install run, so
it belongs in a committed per-host artifact rather than being re-asked
each install.

## Solution

Add a separate live-CD tool, `.os/tools/pick.sh` (see Pre-Install
Picker in CONTEXT.md), that generates `install.jsonc` from a
fzf-driven wizard. The picker prompts for exactly two things — host
and target disks — and pulls every other field from a per-host
Install Template (`.os/hosts/<hostname>/install.template.jsonc`,
merged with `.os/hosts/core/install.template.jsonc`).

Workflow on the live CD becomes: clone repo → `./pick.sh` → review
`install.jsonc` → `./install.sh`. The picker offers `[w]rite &
install` on its review screen to fuse the last two steps when wanted.

`install.sh` is untouched and has no idea the picker exists. The
picker is a config-builder; the installer remains a pure
config-applier. Hosts without an `install.template.jsonc` are
silently omitted from the picker; they remain installable by
hand-editing `install.jsonc`.

The architectural rationale and rejected alternatives (flag on
`install.sh`, auto-fallback on missing config) are recorded in
ADR-0010.

## User Stories

1. As an operator booting the live CD on a new machine, I want a
   single command (`./pick.sh`) that generates `install.jsonc` from
   the values that vary per machine, so that I don't hand-edit a
   JSONC file on a transient ISO.
2. As an operator, I want the picker to self-install its
   dependencies (`fzf`, `jq`) via `pacman -Sy`, so that I can run it
   on a fresh Arch live CD with no setup.
3. As an operator, I want to pick the target host from a fzf list of
   `.os/hosts/<hostname>/` directories that ship an Install Template,
   so that incomplete or legacy hosts don't show up as choices.
4. As an operator, I want the chosen host's directory name to become
   the `hostname` in the generated `install.jsonc` without an
   override prompt, so that the implicit dir-name ↔ hostname link
   stays a hard invariant.
5. As an operator, I want every per-machine field (bootloader,
   locale, timezone, keymap, kernel, ZFS pool/dataset names,
   `environment.desktop`, `environment.gpu`, `options.encryption`,
   `options.impermanence.*`, `options.age_key_url`) committed in the
   host's Install Template, so that the picker never re-asks
   properties of the machine.
6. As an operator, I want the picker to first ask `INSTALL_MODE`
   (single / mirror / raidz), so that disk selection is constrained
   to a known layout rather than inferred after the fact.
7. As an operator, I want the disk picker to list devices under
   `/dev/disk/by-id/*` only, so that I get stable identifiers that
   work with ZFS root.
8. As an operator, I want the live-medium device automatically
   filtered out of the disk list, so that I can't accidentally
   install onto the USB I booted from.
9. As an operator, I want a fzf preview pane showing `lsblk`,
   `smartctl -i`, and the existing partition table for the focused
   disk, so that I can tell which physical disk is which before
   committing.
10. As an operator, I want disk selection enforced against
    `INSTALL_MODE` (1 for single, ≥2 for mirror, ≥3 for raidz), so
    that I cannot produce a layout the installer would reject later.
11. As an operator, I want to multi-select disks with `<TAB>` and
    confirm with `<ENTER>`, so that I follow the standard fzf
    multi-select idiom.
12. As an operator, I want the picker to validate the assembled
    `install.jsonc` through `lib/install-config.sh` before showing
    the review screen, so that picker-time errors never surface
    later at install time.
13. As an operator, I want a final review screen showing the JSONC
    that will be written, plus a diff against any existing
    `install.jsonc`, so that I can spot mistakes before committing.
14. As an operator, I want the review screen to offer `[w]rite &
    install / [w]rite only / [e]dit / [a]bort`, so that I can choose
    between a one-step pipeline and an explicit two-step workflow.
15. As an operator choosing `[w]rite only`, I want the picker to
    stop after writing `install.jsonc`, so that I can review,
    commit, or scp the file before invoking the installer.
16. As an operator choosing `[w]rite & install`, I want the picker
    to exec `install.sh` in the same shell, so that the live-CD
    workflow is one command end-to-end.
17. As an operator choosing `[e]dit`, I want the picker to loop
    back to the relevant prompt, so that I can correct a mistake
    without re-running from scratch.
18. As an operator who runs the picker repeatedly during testing, I
    want the same flow whether `install.jsonc` exists or not, so
    that there is no hidden conditional branch in the UX.
19. As a maintainer, I want the picker to live in `.os/tools/`
    parallel to `save-pkglist.sh` and `impermanence.sh`, so that
    `install.sh` stays a pure applier with no interactive branches.
20. As a maintainer, I want the picker's deep modules (host
    enumeration, template loading, disk enumeration, layout
    validation, config assembly) extracted as pure functions, so
    that they are testable under bats without a TTY or fzf.
21. As a maintainer migrating hosts, I want hosts without an
    `install.template.jsonc` to be invisible to the picker but
    still installable by hand-editing `install.jsonc`, so that the
    picker is opt-in per host.
22. As a maintainer, I want the Install Template to merge with
    `hosts/core/install.template.jsonc` using the same rules as
    Host Config, so that operators don't learn a second merge
    model.
23. As a CI / VM-test maintainer, I want `install.sh` unchanged by
    this work, so that existing VM tests continue to drive the
    installer non-interactively.

## Implementation Decisions

### New tool: `tools/pick.sh`

Live-CD entry point. Self-installs `fzf` and `jq` via `pacman -Sy` at
the top of the script. Orchestrates the deep modules below, runs the
review loop, writes the file, and optionally execs `install.sh`. No
business logic of its own — pure glue.

### Deep modules (pure, testable in isolation)

- **Host enumerator.** Given the hosts directory, returns the list
  of host names that ship `install.template.jsonc`. Hosts without
  the template are silently omitted (decision documented in
  ADR-0010 and CONTEXT.md → Pre-Install Picker).
- **Template loader.** Given a host name, reads
  `hosts/core/install.template.jsonc` and the host's
  `install.template.jsonc` and returns the merged result. Uses
  `lib/jsonc.sh` for parse + deep-merge; merge rules match Host
  Config / Host Core.
- **Disk enumerator.** Given the live medium device, returns the
  sorted list of `/dev/disk/by-id/*` paths excluding the live
  medium and its partitions. Live medium is detected via
  `/run/archiso/bootmnt` or the partition labelled `ARCH_*`.
- **Disk preview formatter.** Given a by-id path, prints a single
  multi-line block combining `lsblk -dno
  NAME,SIZE,MODEL,SERIAL,TRAN`, `smartctl -i`, and the existing
  partition table. Consumed by fzf's `--preview` flag.
- **Layout validator.** Given `INSTALL_MODE` and the count of
  selected disks, returns ok or a human-readable error. Pure rule:
  single ↔ 1, mirror ↔ ≥2, raidz ↔ ≥3.
- **Config assembler.** Given the merged template, the chosen
  hostname, the chosen mode, and the chosen disk list, returns the
  full `install.jsonc` text. The hostname overrides whatever (if
  anything) the template carries; the layout fields are written
  fresh. Every other field passes through from the template
  unchanged.

### Shallow glue (TTY/fzf-coupled, not extracted)

- fzf host picker (single-select)
- fzf disk picker (multi-select with `<TAB>`, preview pane wired to
  the Disk preview formatter)
- Review screen rendering (`diff` against existing `install.jsonc`
  when present) and the four-way prompt
- Final write to `.os/install.jsonc`
- `exec install.sh` hand-off for `[w]rite & install`

### Reused

- `lib/jsonc.sh` for JSONC parsing + merging in the Template
  loader and Config assembler.
- `lib/install-config.sh` for post-assembly validation; the picker
  feeds it the assembled JSONC and surfaces any error before the
  review screen.

### Per-host Install Template

A new file per host, `hosts/<hostname>/install.template.jsonc`,
plus a shared `hosts/core/install.template.jsonc`. Owns every
per-machine field listed in CONTEXT.md → Install Template. Absent
templates make the host invisible to the picker but do not break
hand-editing.

### Workflow contract

The picker writes a fully-populated `install.jsonc` that
`install.sh` reads unchanged. There is no env-var overlay, no
template at install time, and no awareness of the picker in
`install.sh`. The two scripts communicate only through the file on
disk.

### Out-of-band cases

- Live CD has no network → `pacman -Sy fzf jq` fails → picker exits
  with a clear message. Acceptable: the installer itself needs
  network.
- No hosts ship a template → picker exits with a clear message
  pointing at the hand-edit path.
- Picker validation fails after assembly → user is shown the error
  and looped back into edit, not silently dropped.

## Testing Decisions

### What makes a good test here

Tests cover the deep modules' external behaviour: input → output
contracts. They do not assert how `fzf` is invoked, how the review
screen renders, or how the exec hand-off happens — those are
shallow, TTY-coupled, and best validated by running the picker
manually on the live CD.

### Modules to be tested (bats, alongside `.os/tests/*.bats`)

- **Host enumerator.** Fixture hosts dir with mixed
  template-present/absent subdirs; assert returned list matches
  expected.
- **Template loader.** Fixture core + per-host templates that
  exercise the same merge rules as Host Config: scalar override,
  array override, nested object deep-merge. Reuses the existing
  JSONC merge harness pattern.
- **Disk enumerator.** Fake `/dev/disk/by-id/` tree + a fake
  live-medium device; assert the live medium and its partitions
  are excluded and the result is sorted and stable.
- **Layout validator.** Pure rule table: every (mode, count) pair
  → expected ok / error.
- **Config assembler.** Fixture template + picker outputs → assert
  the produced `install.jsonc` round-trips through `lib/jsonc.sh`
  and contains the expected fields. Snapshot-style comparison.

### Prior art in the repo

- `.os/tests/jsonc.bats` — pattern for testing the merge helpers
  the Template loader will reuse.
- `.os/tests/install-config.bats` — pattern for testing the
  validator the picker will call after assembly.
- `.os/tests/layout-common.bats` — pattern for testing the layout
  rule space, directly analogous to the Layout validator.
- `.os/tests/impermanence-common.bats` /
  `.os/tests/impermanence-tool.bats` — pattern for testing a
  `tools/*.sh` script's deep helpers without exercising its
  interactive surface.

## Out of Scope

- Changing `install.sh` in any way. ADR-0010 commits to leaving the
  installer untouched.
- Replacing the JSONC merge semantics. The Template loader uses
  whatever `lib/jsonc.sh` already does for Host Config / Host Core.
- A non-fzf fallback UI. We accepted broad fzf scope earlier; if
  fzf is unavailable, the picker exits with a clear message.
- Editing the Install Template via the picker. The picker reads
  templates; it does not write them. Updating per-machine fields
  is done by editing the template in the repo.
- Encryption passphrase collection. `install.sh` continues to
  prompt for the passphrase as today; the picker does not handle
  secrets.
- A picker for user-level fields (User Config, User Core, secrets).
  Out of scope.
- Offline operation. The picker requires network for its own
  `pacman -Sy`; the installer requires network anyway for
  pacstrap.
- Re-installs that preserve existing data. The picker has no
  knowledge of prior installs; if `install.jsonc` exists it is
  shown as a diff and overwritten on confirm.
- Per-host validation that the chosen disks are *appropriate*
  (size, type) for the host. Layout validation is purely against
  `INSTALL_MODE` count; physical suitability is the operator's
  call.

## Further Notes

- ADR-0010 records the architectural decision (separate tool, not
  a flag on `install.sh`); CONTEXT.md → Pre-Install Picker and
  Install Template define the domain terms used throughout this
  PRD.
- Pickable-host enumeration uses presence of
  `install.template.jsonc` as the signal — not a `pickable: true`
  flag — to keep the template the single source of truth about
  whether a host is picker-ready.
- The review screen's diff is most useful during repeat picker
  runs (e.g. swapping disks during testing); on a fresh live CD
  with no prior `install.jsonc` the diff degrades to a plain
  cat-of-the-output, which is fine.
- Migration of existing hosts to picker-readiness happens
  lazily: each host gains an `install.template.jsonc` when its
  owner wants picker support. The repo can ship mixed states
  indefinitely.
