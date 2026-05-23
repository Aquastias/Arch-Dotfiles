Status: ready-for-agent

# fzf-powered pick with disk preview pane

## Parent

`.scratch/pre-install-picker/PRD.md`

## What to build

Replace the plain `select` prompts from slice 1 with `fzf`, and add a
preview pane for the disk picker so the operator can identify
physical disks before committing.

End-to-end behaviour is unchanged from slice 1 (single-disk install,
no review screen yet) — this slice only upgrades the UI surface.

### Self-install dependencies

At the top of `tools/pick.sh`, ensure `fzf` and `jq` are present via
`pacman -Sy --noconfirm fzf jq`. Missing-network failure exits with a
clear message pointing at the same constraint that gates pacstrap.

### Host picker

Replace the `select` prompt with `fzf` single-select against the
output of the Host enumerator. No preview pane required for hosts.

### Disk picker

Replace the `select` prompt with `fzf` single-select (multi-select
arrives in slice 3) against the output of the Disk enumerator. Wire
a preview pane via `fzf --preview` to the new Disk preview formatter.

### Deep module introduced

- **Disk preview formatter.** Given a `/dev/disk/by-id/*` path,
  prints a single multi-line block combining:
  - `lsblk -dno NAME,SIZE,MODEL,SERIAL,TRAN` for the resolved
    device
  - `smartctl -i` (header info only) when `smartmontools` is
    available; skip cleanly otherwise
  - the existing partition table summary (`lsblk -no
    NAME,SIZE,FSTYPE,LABEL,PARTLABEL` of the device tree)

The formatter is a pure function from by-id path to formatted text.
Side-effecting tool invocations live inside it but its output is
deterministic given the same inputs, so it is snapshot-testable.

### Out of this slice

- Multi-select disks and ZFS mirror/raidz modes (→ slice 3).
- Review screen, diff, four-way prompt, edit loop, install
  hand-off (→ slice 4).

## Acceptance criteria

- [ ] `tools/pick.sh` self-installs `fzf` and `jq` via `pacman -Sy
      --noconfirm` at start; missing network fails with a clear
      message.
- [ ] Host pick uses fzf single-select against the Host
      enumerator's output.
- [ ] Disk pick uses fzf single-select with `--preview` wired to
      the Disk preview formatter.
- [ ] Preview pane renders `lsblk`, `smartctl -i` (when available),
      and partition table for the focused disk.
- [ ] End-to-end behaviour matches slice 1: a single-disk install
      produces the same `install.jsonc` content as before for the
      same picks.
- [ ] bats tests cover the Disk preview formatter — snapshot-style
      assertions against a fixture by-id path and stubbed `lsblk` /
      `smartctl` outputs.
- [ ] All slice-1 tests continue to pass; `tests/run.sh` and
      `tests/shellcheck.sh` pass.

## Blocked by

- `.scratch/pre-install-picker/issues/01-mvp-picker-end-to-end.md`
