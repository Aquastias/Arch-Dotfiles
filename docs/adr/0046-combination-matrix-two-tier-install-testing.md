# Combination-matrix install testing in two tiers

Verify that no menu-reachable install combination errors, by testing a
generated **Combination Matrix** in two tiers: a no-VM tier that assembles
and validates the *exhaustive* storage cluster on every bats run, and a VM
tier that installs a *pairwise* subset (plus pinned historical-bug seeds)
through the real back-end. Axes, values, and exclusions are derived from the
menu's own option functions, not a hand-kept spec.

Builds on ADR 0035 (profile-driven VM Harness), ADR 0036 (unified profile /
Effective Config), ADR 0039 (Guided Installer), ADR 0040 + ADR 0043
(Filesystem Adapter axis + per-group filesystem). Consumes the Guided
Installer's assembler and `validate_install_context`.

## Considered Options

- **(a)** Exhaustive Cartesian product through VMs — rejected. The menu's
  full product is effectively infinite (~26 fields, many multi-valued); even
  the storage cluster alone at ~15-20 min/VM caps coverage at a few dozen
  combinations ever. Cannot approximate "every menu choice".
- **(b)** Single VM tier at pairwise — rejected as the *whole* answer. It
  finds back-end bugs but leaves the "menu let me pick something that won't
  assemble" class checked only where a VM happens to land, and every check
  costs a VM.
- **(c)** Hand-authored constraint spec feeding a matrix generator — rejected.
  A second copy of the menu's validity rules drifts the day an axis changes,
  so the matrix silently tests a fiction.
- **(d)** Two tiers — no-VM exhaustive assembly+validate over the storage
  cluster, plus pairwise VM install/boot — with axes/values/exclusions
  derived from the menu functions. Chosen.

## Decision

**Two failure classes, two oracles.** A menu choice can fail two ways, at
wildly different cost:

- *Menu/assembly* — the menu admits a combination that assembles to an
  invalid or broken config. Cheapest oracle: `assemble` →
  `validate_install_context` on the host, ~ms/cell, no VM.
- *Back-end/install* — a *valid* config the installer mishandles on real
  storage. Only oracle: a real VM install (+ boot).

**Tier 1 — no VM, exhaustive where it interacts.** Exhaustive Cartesian over
the **storage cluster** (root filesystem × encryption × impermanence ×
topology × disk-mode × per-group data-pool filesystem/encryption — including
mixed-filesystem cells such as a zfs root with a btrfs/ext4/xfs data pool),
each assembled and passed through `validate_install_context`. Independent
passthrough scalars (kernel, bootloader, desktop, gpu, mirrors, sysctl …) are
each swept once, not crossed against storage. Runs inside `tests/run.sh` and
CI — the always-on guarantee.

**Tier 2 — VM, pairwise + pinned seeds.** A 2-wise cover over the
install-affecting axes (the storage cluster plus kernel, bootloader, desktop,
gpu, swap), unioned with a pinned list of historically-broken tuples
(zfs-root+btrfs-pool, ext4-root+zfs-pool, btrfs-raid1-encrypted-multi,
xfs-root, zfs-keyfile-on-root+encrypted-pool). Each cell reuses **Tier 1's
assembler** to produce the Effective Config and installs it through the
config seam (`install.sh <config-file>` → the same bytes the menu emits, plus
picked disks), *not* through `--guided`. The Guided runtime itself is
combination-independent and stays covered by the existing fixed `--guided`
smoke profiles.

**Per-cell oracle**, keyed on the cell:

| Cell | Oracle |
| --- | --- |
| plain | `INSTALLER-EXIT-0` + first-boot sentinel |
| impermanent | `INSTALLER-EXIT-0` + `verify.rollback` (two-boot: ephemeral wiped, persistent survived) |
| encrypted | same as its plain/impermanent peer — the **Console Answerer** unlocks it headlessly (below) |

Encryption is *not* a boot-verify carve-out: a **Console Answerer** drives the
real passphrase-unlock path exactly as a human would — the closest-to-reality
oracle. The harness already injects `console=ttyS0,115200` into the installed
system's loader entries for boot-verify, which the comment notes routes
"emergency prompts" to serial; the LUKS/zfs prompt therefore appears in the
serial log the watcher already tails. The Answerer (1) detects the prompt by
its known patterns (the `encrypt` hook, `systemd-cryptsetup`, and zfs-native
`load-key` prompts differ), (2) writes the known **test passphrase** to the
serial char device — *not* `virsh send-key`, because with `console=ttyS0` the
prompt reads from `/dev/console`=serial, not the emulated keyboard — and (3)
bounds retries into an `ENCRYPTED-BOOT-FAIL` result rather than a hang. The
existing serial-console cmdline injection (systemd-boot loader entries) gains a
**GRUB parity** path (`GRUB_CMDLINE_LINUX`) so GRUB cells' prompts land on
serial too. This closes the encrypted-boot gap the project already hit (the
recorded headless-verify reboot-loop finding) and is built as its own slice.

**Derivation, not duplication.** The generator sources `lib/config/*` and
`lib/guided-controller.sh` and walks their option functions
(`_ctl_topologies_for_fs`, `menu_rows`, the picker/validation min-disk rules),
so unreachable cells are structurally impossible and the matrix tracks the
menu automatically. The pairwise draw is seeded (fixed → deterministic).

**Staying in sync is enforced, not remembered.** New *values* on an existing
axis (a filesystem, a topology, a kernel) are picked up live and tested next
run. A new *axis* (a whole new `_MENU_FIELDS` entry) is the one thing that
can't be auto-classified — install-affecting? storage-interacting? light or
heavy? — so the generator holds an **axis registry** mapping every menu field
to its role (`storage-cluster` / `scalar-sweep` / `pairwise-affecting` /
`inert`, + light/heavy weight) and asserts on every run that the registry
covers `_MENU_FIELDS` *exactly*. Adding a menu field without registering it
**hard-fails** the generator (`unclassified axis <path>`). CI then runs
`matrix.sh gen`, regenerates the coverage summary, and diffs both against the
committed snapshots — any coverage change fails CI until regenerated and
committed. A behavior-preserving refactor (e.g. via
`/improve-codebase-architecture`) regenerates to a no-op; one that touches menu
options trips the same assertion/diff. The contract is documented under
`docs/agents/` so menu-editing and refactor workflows know to run `matrix.sh
gen` as part of wrap-up.

**Artifacts.** `.os/tools/matrix.sh` is one entrypoint with subcommands
(`gen` / `emit <cell-id>` / `run [--smoke|--full]`), mirroring `vm.sh`. Two
committed records, each regenerated and diffed in CI:

- **Matrix Manifest** (`.os/tests/vm/matrix-manifest.jsonl`, one JSON line per
  cell: cell-id + axis assignment) records the **Tier-2 set only** — the
  expensive, selective pairwise+seed cells worth reviewing, pinning, and
  reproducing by id. CI regenerates the Tier-2 selection and diffs it (the
  "did you mean to change VM coverage?" gate).
- **Coverage summary** (derived axes → values → exclusions + per-tier cell
  counts, e.g. `storage-cluster: 36`) is the drift guard for the *constraint
  model*: a silent shrink (e.g. raidz2 dropped from a topology cycle) surfaces
  as a one-line change + a count delta, which Tier-1 bats alone would not
  catch since it still passes with fewer, all-valid cells.

Tier 1's exhaustive storage cluster is regenerated live in the bats run
(`.os/tests/config/matrix-assembly.bats`), not enumerated in a committed file.
VM Profiles are never committed: `matrix.sh emit <cell-id>` materializes any
cell to a tmpfs profile on demand for isolated re-runs. Disk count per cell is
`Σ disk_count` (via `skeleton_total_disks`) at 20 GiB/disk; the resilience
axes (`by_id`, `reorder_boot_disks`, `resilience`, `dirty_cache`) stay on
their curated profiles, not matrixed.

**Orchestration.** Tier 2 is on-demand (needs libvirt+KVM), default 3-way
parallel with a `--smoke` (pinned seeds only) / `--full` (whole pairwise)
split. Per-cell `timeouts.install` is stamped from a **two-band** tag the
generator derives from the cell's cost drivers — *light* (~45 min: no desktop,
no nvidia, no AUR) vs *heavy* (~90 min: any desktop, nvidia DKMS, or AUR/paru)
— so a hung light cell fails fast while heavy cells don't false-fail; env
overrides still win. A **host-resource guard** runs before and between
launches: a preflight
computes `max_parallel` from `MemAvailable` minus host headroom (8 GiB/VM,
paru OOMs below) and checks `/dev/kvm`, `libvirtd`, and free image-dir disk; a
per-launch gate blocks until RAM is free rather than over-committing — the run
never freezes the host. Failures do not fail-fast: all cells run, per-cell
logs are kept (`arch-zfs-test-<cell-id>.log`), a summary table prints
PASS/FAIL/SKIP (encrypted-boot shown as SKIP, not FAIL), and the driver exits
non-zero if any cell failed.

## Consequences

- "No error for any menu choice" becomes a checked property: Tier 1 covers
  *every* menu-reachable storage combination on every test run; Tier 2 proves
  the risky pairs on real storage.
- The matrix cannot drift from the menu or emit an impossible cell — both are
  consequences of deriving from the menu's own functions.
- Tier 2's fidelity gap is exactly the interactive front-end (fzf render,
  in-guest picker), which is combination-independent and covered elsewhere;
  the back-end sees identical bytes either way.
- Encrypted cells are fully boot-verified via the Console Answerer (real
  passphrase over serial), including encrypted-impermanent rollback — no
  install-only carve-out. The Answerer is a distinct build slice and carries
  its own fragility budget (prompt-pattern drift, serial timing, GRUB parity);
  a hard failure surfaces as `ENCRYPTED-BOOT-FAIL`, never a hang.
- GPU is a full matrix axis {auto, amd, nvidia, intel}. Drivers install but
  cannot be exercised on a virtual GPU, so `gpu≠auto` is an install-only
  check (packages resolve/build clean), not a functional one. `nvidia` is a
  DKMS build against the kernel headers, so `nvidia × kernel` is a pinned
  pairwise pair; `amd+nvidia` additionally pulls `envycontrol` from the AUR.
- Adding a menu axis or filesystem forces a conscious manifest update (the CI
  diff fails), keeping the covered set honest.
