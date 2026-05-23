Status: done

# Mode-then-disks: mirror and raidz multi-disk layouts

## Parent

`.scratch/pre-install-picker/PRD.md`

## What to build

Extend the picker to support ZFS `mirror` and `raidz` layouts in
addition to `single`. The flow becomes **mode-then-disks**: prompt
for `INSTALL_MODE` first, then constrain the disk picker's
multi-select against that mode.

### Mode prompt

Before the disk picker, add an `INSTALL_MODE` prompt via `fzf`
single-select over the three values `single`, `mirror`, `raidz`. The
chosen mode is written verbatim to `install.jsonc` and drives the
Layout validator and disk picker behaviour below.

### Disk picker (extended)

Switch the disk picker from single-select to fzf **multi-select**
with `<TAB>` to toggle and `<ENTER>` to confirm. The Disk preview
formatter from slice 2 keeps working unchanged.

After the user confirms a selection, run the Layout validator. On
failure, surface the error and re-prompt; on success, proceed to
Config assembly.

### Layout validator (extended)

Pure rule table, extended from slice 1:

- `single` → exactly 1 disk
- `mirror` → ≥ 2 disks
- `raidz` → ≥ 3 disks

Errors are human-readable and name both the chosen mode and the
required count.

### Config assembler (extended)

The assembler already accepts a `disks[]` array; this slice exercises
the multi-disk path. The generated `install.jsonc` carries the full
list of by-id paths under whatever field the existing Install Config
schema expects for multi-disk layouts (see Layout Module / Install
Config in CONTEXT.md).

### Out of this slice

- Review screen, diff, four-way prompt, edit loop, install
  hand-off (→ slice 4). This slice still writes `install.jsonc`
  unconditionally on success.

## Acceptance criteria

- [ ] `tools/pick.sh` prompts for `INSTALL_MODE` (single / mirror /
      raidz) before the disk picker.
- [ ] Disk picker supports fzf multi-select via `<TAB>` and
      `<ENTER>`.
- [ ] Selection violating the mode's disk-count rule is rejected
      with a clear error and re-prompted.
- [ ] Valid `mirror` and `raidz` selections produce
      `install.jsonc` files that pass `lib/install-config.sh`
      validation and are consumed by `install.sh` unchanged.
- [ ] bats tests for the Layout validator cover the full rule
      table: every (mode, count) pair → expected ok / error.
- [ ] bats tests for the Config assembler include multi-disk
      fixtures for `mirror` and `raidz`.
- [ ] All slice-1 and slice-2 tests continue to pass;
      `tests/run.sh` and `tests/shellcheck.sh` pass.

## Blocked by

- `.scratch/pre-install-picker/issues/02-fzf-with-preview.md`
