# Combination Matrix

Running notes for agents working on the Combination Matrix (ADR 0046) — the
two-tier "no menu-reachable install combination errors" testing. Entry point:
`.installer/tools/matrix.sh` (`gen` / `emit <cell-id>` / `run`);
generator/adapter
logic in `.installer/lib/matrix/*.sh`; Tier-1 assembly bats under
`.installer/tests/matrix/`.

## Test gates (ADR 0078)

`.installer/tests/run.sh` has three modes:

- `--fast` — curated install-correctness subset (config + the validator
  tier + layout + zfs + wipe), ~30 s wall. The pre-push gate.
- `--full` (default) — every bats file, the always-on tier.
- `--vm` — on-demand VM smoke (`matrix.sh run --smoke`); aborts cleanly
  where `/dev/kvm` is absent.

Enable the opt-in pre-push hook once: `git config core.hooksPath
.githooks` (skip one push with `SKIP_FAST_TESTS=1 git push`). Judge speed
by total CPU, not wall, on a loaded box. Coverage of past install breaks
is tracked in [[test-regression-catalog]].

## The sync contract: menu-derived, CI-enforced

The matrix axes, values, and exclusions are **derived from the menu's own
option functions** (`_ctl_built_root_filesystems`, `_ctl_topologies_for_fs`,
the pickers/validation) — never a hand-kept spec — so the matrix cannot drift
from what the installer menu offers. Two guards keep it honest:

1. **Axis Registry completeness** (issue 02) — `matrix.sh gen` aborts if a menu
   field (`_MENU_FIELDS`) is unclassified or a registry entry is stale.
2. **Committed records + drift guard** (issue 08) — two files are checked in:
   - `.installer/tests/vm/matrix-manifest.jsonl` — the Tier-2 set (one cell/line): the
     expensive, selective cells worth pinning/reproducing.
   - `.installer/tests/vm/matrix-coverage.txt` — a diffable snapshot of resolved axes →
     values → exclusions + per-tier cell counts. A silent constraint shrink
     (fewer valid cells — which Tier-1 bats still passes) shows here as a
     one-line change + a count delta, not a wall of vanished rows.

   `tests/matrix/matrix-records.bats` regenerates both and diffs them against
   the committed copies, so a menu change that isn't followed by a regen fails
   the suite. Tier-1's exhaustive list stays regenerated-live (not committed);
   VM Profiles are never committed (materialized via `emit`).

**Wrap-up step (do this after any menu / constraint / axis change, and in the
`/improve-codebase-architecture` flow):** run `./.installer/tools/matrix.sh gen`
and
commit the updated `matrix-manifest.jsonl` + `matrix-coverage.txt`. The suite
will otherwise go red on the drift guard.

The rest of this file records the environment gotchas that bite a live Tier-2
run.

## Per-disk size: 40 GiB, not the PRD's 20

The synthesizer provisions **40 GiB** per disk (`MATRIX_DISK_GIB`), not the 20
GiB the PRD estimated. A real zfs root doesn't fit in 20 GiB: with the default
~5 GiB swap zvol (refreserved) + the OS + impermanence datasets, a ~16 GiB rpool
fails with `cannot create rpool/swap: out of space` (VM-observed on the
impermanent cell). qcow2 is sparse, so the larger virtual size costs nothing on
disk. Shrink swap or raise the size if you revisit this.

## Tier-2 VM runs from an agent environment

Tier-2 (`matrix.sh run`) installs + boot-verifies a cell in a real VM via the
VM Harness. Two environment hazards, both independent of the matrix code:

- **archzfs ISO lag.** The ISO resolver picks the newest archived Arch ISO
  whose kernel archzfs ships a prebuilt module for. When archzfs trails the
  live kernel, the resolver returns an EMPTY ISO and the VM has no boot medium
  (`No bootable option or device`). Work around it by pinning a cached ISO:
  `ISO_URL_OVERRIDE=file:///path/to/archlinux-<date>-x86_64.iso`. The install
  then builds ZFS via the DKMS fallback against the ISO's kernel — slower, but
  it boots. Slice 05's profile synthesizer should own this ISO/oracle policy
  rather than leaving it as a manual override.

- **Local-repo serving.** The guest `git clone`s `REPO_URL` (default GitHub)
  for the installer code. To test unpushed local work, serve the repo at HEAD
  with `git daemon` and point `REPO_URL` at the libvirt gateway
  (`git://192.168.122.1/<repo>`). The daemon serves committed content only —
  the cell's Effective Config still reaches the guest inline via the profile's
  `.install` (the config seam), so uncommitted matrix code is not needed in the
  guest. In a sandboxed agent shell the daemon dies with its launching
  command's process-group teardown, so co-host `git daemon` and `matrix.sh run`
  in a single long-lived (background, sandbox-disabled) invocation.

See also [[dotfiles-vm-smoke-agent-context]] for the general VM-from-agent
constraints (one VM per job, 8 GiB RAM to avoid paru OOM, encrypted roots can't
headless boot-verify without the Console Answerer).
