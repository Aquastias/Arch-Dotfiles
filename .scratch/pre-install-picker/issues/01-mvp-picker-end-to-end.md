Status: ready-for-agent

# MVP picker: end-to-end, single-disk, plain `select`

## Parent

`.scratch/pre-install-picker/PRD.md`

## What to build

A first end-to-end `tools/pick.sh` that produces a valid
`install.jsonc` for a single-disk install. No fzf, no preview, no
review screen — those land in later slices. This slice exists to put
every deep module in place behind a working pipeline.

The picker prompts the operator (via plain `select`) for:

1. **Host** — one of the `hosts/<hostname>/` directories that ships
   `install.template.jsonc`. The chosen dir's basename becomes the
   `hostname` in the generated config; no override.
2. **Disk** — one `/dev/disk/by-id/*` path, with the live medium and
   its partitions filtered out.

Mode is hardcoded to `single` in this slice. The picker assembles the
final JSONC by loading the merged Install Template (core + host) and
overlaying `hostname` + the chosen disk + `INSTALL_MODE=single`.

Before writing, the picker validates the assembled config via
`lib/install-config.sh`. Validation failure prints the error and
exits non-zero; no review/edit loop yet.

On success, the picker writes `.os/install.jsonc` and exits. The
operator runs `./install.sh` separately.

### Deep modules introduced

- **Host enumerator.** Returns the list of hosts that ship an
  `install.template.jsonc`. Hosts without the template are silently
  omitted.
- **Template loader.** Reads `hosts/core/install.template.jsonc` +
  `hosts/<host>/install.template.jsonc` and returns the merged
  result using `lib/jsonc.sh`. Merge rules match Host Config / Host
  Core.
- **Disk enumerator.** Returns sorted `/dev/disk/by-id/*` paths
  excluding the live medium and its partitions. Live medium detected
  via the partition labelled `ARCH_*` or via `/run/archiso/bootmnt`.
- **Layout validator.** Pure rule: `single` ↔ exactly 1 disk. Errors
  for any other count. (Mirror/raidz arrive in slice 3.)
- **Config assembler.** Given merged template + hostname + mode +
  disks, returns the full `install.jsonc` text. Hostname overrides
  any template value; layout fields are written fresh; every other
  field passes through from the template unchanged.

### Install Template files

- New `hosts/core/install.template.jsonc` with the truly shared
  defaults (locale, timezone, keymap, kernel, ZFS pool/dataset
  names, etc.).
- New `hosts/<existing-hostname>/install.template.jsonc` for at
  least one existing host so the picker has something to offer.
  Choose the host already used as the primary example in the repo.

### Out of this slice

- fzf, preview pane, multi-select (→ slice 2).
- Mirror / raidz multi-disk layouts (→ slice 3).
- Review screen, diff, four-way prompt, edit loop, install
  hand-off (→ slice 4).
- `pacman -Sy fzf jq` self-install (→ slice 2; this slice has no
  external dependency beyond what the live CD ships).

## Acceptance criteria

- [ ] `tools/pick.sh` exists, is executable, and runs end-to-end
      against a host that ships `install.template.jsonc`.
- [ ] `hosts/core/install.template.jsonc` and at least one
      `hosts/<hostname>/install.template.jsonc` exist and define
      every per-machine field listed in CONTEXT.md → Install
      Template.
- [ ] Hosts without `install.template.jsonc` do not appear in the
      host pick list.
- [ ] The chosen host directory's basename is written verbatim to
      the `hostname` field of the generated `install.jsonc`.
- [ ] The live medium device and its partitions are excluded from
      the disk list.
- [ ] The assembled `install.jsonc` passes validation via
      `lib/install-config.sh`; validation failure exits non-zero
      with the error visible to the operator.
- [ ] The generated `install.jsonc` is consumed by `install.sh`
      unchanged (`install.sh` is not modified by this slice).
- [ ] bats tests cover the Host enumerator, Template loader, Disk
      enumerator, Layout validator, and Config assembler — fixture
      patterns analogous to `tests/jsonc.bats`,
      `tests/install-config.bats`, `tests/layout-common.bats`,
      `tests/impermanence-common.bats`.
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass.

## Blocked by

None - can start immediately.
