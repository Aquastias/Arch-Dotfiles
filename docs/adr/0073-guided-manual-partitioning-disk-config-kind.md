# Guided Manual Partitioning as a feature-light disk-config kind

---
Status: accepted (amends ADR 0036's "a profile declares the full pool skeleton"
premise; sits beside the ADR 0034/0040/0043 layout adapters)
---

The Guided Installer gains a **Manual partitioning** on/off toggle on the
**Disks** category. Off is the installer's predefined (auto) behaviour — the
declarative pool skeleton the layout adapters consume, unchanged. On hands the
whole partition table to the operator (`cfdisk`, archinstall-style) and installs
onto the result, at the cost of every pool-dependent feature. It is a deliberate
**escape hatch**, not a fourth thing you commit.

## The kind split

`disk_config` becomes a discriminated **kind**:

- **`auto`** — today's pool skeleton (`mode`, `os_pool`, `storage_groups[]`,
  `data_pools[]`) fed to the filesystem × mode layout adapters. The default; no
  behaviour changes.
- **`manual`** — a flat `partitions[]` list, each entry
  `{ mountpoint, fs, format|keep }`, produced by the operator's `cfdisk` session
  and a post-`cfdisk` assignment step. The back-end dispatches on the kind the
  same way `dispatch.sh` dispatches on filesystem today.

Bolting `partitions[]` onto the pool skeleton was rejected: the two are
genuinely different shapes (topology/groups vs a flat mountpoint list), and a
hybrid corrupts both the schema and the validation contract.

## Feature envelope — deliberately minimal

Manual bypasses the pool machinery, so everything that lives on it is
**disabled**: ZFS/pool layouts, disk encryption (Encryption Editor),
impermanence (Impermanence Editor), multi-disk data pools / storage groups and
pool owners, managed swap (the zswap default, ADR 0045), and the ESP-size field.
Turning manual on fires a **one-time confirm notice** naming this cost; the
disabled fields stay **shown-but-locked** on the Disks screen (not hidden) so the
operator sees exactly what was traded away. "Full manual" — feeding a hand-drawn
table back into ZFS/encryption/impermanence — was rejected as a second installer:
that capability already exists as the declarative `auto` path, and re-importing
it under manual would double the surface for no new expressiveness.

## Flow and validation

Pick the target disk → launch `cfdisk` on it (where the operator cuts any swap
partition themselves, type `8200`) → on exit re-read the table (`lsblk`) → assign
each partition a **mountpoint** (`/`, `/boot/efi`, `/home`, … or `[swap]`), a
**filesystem** (ext4/xfs/btrfs/fat32), and **format-or-keep** (mkfs, or leave
existing data and only mount). ESP (`ef00`) and swap (`8200`) pre-fill from the
partition type; unassigned partitions are ignored. A viable layout requires
**exactly one root (`/`)** and **exactly one FAT32 ESP (`/boot/efi`)**.

## Lifecycle — interactive, Proceed-only, transient

A hand-drawn table cannot be replayed from a committed file, so manual breaks the
committed-audit-artifact contract by nature. It is therefore:

- **Guided Installer only** — never the `--profile` Pre-Install Picker or the
  unattended `install.sh <config-file>` path, both of which assume a declared
  layout.
- **Proceed-only** — no Save Profile, no Export.
- **Transient** — the partition assignment never reaches a committed or exported
  artifact, mirroring the device-less invariant (ADR 0036).
- **Reversible and non-destructive** — auto↔manual toggles without losing either
  side's Config State overrides, like every other guided choice.

## Considered options

- **Pre-mounted configuration** (archinstall's third item: operator mounts
  everything under `/mnt`, installer only pacstraps) — **not shipped**. It is a
  different front-end shape (no `cfdisk`, no assignment — "trust my mounts") and
  would turn the boolean toggle into a three-way with a doubled validation
  surface. Cheap to add later as a second toggle if manual proves out.
- **Manual as a committable profile field** — rejected: nothing device-less to
  commit, and it would violate ADR 0036's reproducibility invariant.

## Consequences

- The Combination Matrix and VM harness gain a manual case, which is
  **VM-verifiable only** end-to-end (it drives `cfdisk` and touches real
  partitions); the pure seams — the `disk_config` kind schema, the `partitions[]`
  accessors, the assignment/validation logic, and the menu lock/notice model —
  are covered headless in bats.
- The Disks screen’s locked-field rendering is new menu chrome: dependent fields
  must render **shown-but-locked** under an active manual toggle, distinct from
  the existing hidden-for-ext4/xfs impermanence rule (ADR 0040).
