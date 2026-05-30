Status: ready-for-agent

# PRD: Fetch archzfs-Compatible ISO tool

References: ADR 0023 (archzfs-Compatible ISO, not the latest Arch).
CONTEXT.md term "archzfs-Compatible ISO". Reuses
`lib/iso-resolver.sh::iso_resolver_get_zfs_compatible`.

## Problem Statement

I install Arch + ZFS by downloading "the latest" ISO from
archlinux.org and booting it — that is what the README tells me to
do. But the latest ISO ships a kernel newer than archzfs tracks, so
the DKMS build in `01-bootstrap-zfs.sh` fails: the ZFS module never
lands for the running kernel and `modprobe zfs` reports the module is
not found. (Concrete incident: a live ISO running kernel `7.0.x`
against ZFS `2.4.2` — DKMS built for the wrong kernel and `modprobe
zfs` had nothing to load.)

The repo already solves this for VM testing — `_harness.sh` resolves
the newest archzfs-compatible archived ISO via
`iso_resolver_get_zfs_compatible`. But there is no human-facing path
to that same compatible ISO for flashing a USB stick, and the README
actively points operators at the wrong ISO. Today I am left bisecting
Arch releases by hand to find one ZFS will build against.

## Solution

A tool, `.os/tools/fetch-iso.sh`, that I run on my current machine
(this dotfiles repo, on Arch) before I boot anything. It downloads
the newest archzfs-Compatible ISO into `~/Downloads` (or a directory
I pass), verifies its sha256 against Arch's published checksums, and
prints the ISO path plus a one-line flashing hint. It does not flash
the USB — I do that with my own tool.

The README Quick Start gains a "Prepare the install media" step ahead
of "Boot the ISO", pointing at this tool and explaining why the
latest Arch ISO will not work. The decision is recorded in ADR 0023
and the term in CONTEXT.md.

## User Stories

1. As an operator, I want a repo-blessed tool that downloads an Arch
   ISO ZFS can actually build against, so that I stop bisecting Arch
   releases by hand.
2. As an operator, I want the tool to pick the newest
   archzfs-Compatible ISO automatically, so that I get the most
   recent ISO that still works.
3. As an operator, I want the ISO saved to `~/Downloads` by default,
   so that it is where I expect to find it when flashing.
4. As an operator, I want to pass a custom output directory, so that
   I can drop the ISO on a larger or different volume.
5. As an operator, I want the tool to create the output directory if
   it is missing, so that I do not hit a "directory does not exist"
   error from the resolver.
6. As an operator, I want the tool to reuse an already-downloaded
   ISO, so that re-runs do not redownload ~1 GB.
7. As an operator on Arch without jq/curl, I want the tool to install
   them for me, so that a missing dependency does not stop me.
8. As an operator, I want only the dependency install to require
   sudo, so that the download itself runs unprivileged.
9. As an operator, I want the tool to verify the ISO's sha256 before
   I flash, so that a corrupt or truncated download is caught early
   rather than mid-install or at boot.
10. As an operator, I want a clear error and the bad file removed on
    a checksum mismatch, so that I cannot accidentally flash a
    corrupt ISO.
11. As an operator, I want the tool to print the absolute ISO path on
    success, so that I can paste it straight into my flash command.
12. As an operator, I want a one-line flashing hint (`dd`) plus a
    mention of Ventoy/Impression/Rufus, so that I know how to get the
    ISO onto the USB regardless of my tooling.
13. As an operator, I want the tool to fail loudly with a clear
    message if archzfs lists no supported kernels or no archived ISO
    matches, so that I understand why no ISO came back.
14. As an operator following the README, I want a "Prepare the
    install media" step before "Boot the ISO", so that the ordering
    matches reality (fetch on my current machine, then boot).
15. As an operator, I want the README to explain why I cannot use the
    latest Arch ISO, so that I stop reaching for
    archlinux.org/download.
16. As an operator, I want the README to reference the
    archzfs-Compatible ISO concept, so that I can read its precise
    definition in CONTEXT.md.
17. As an operator, I want the tool runnable directly from the cloned
    dotfiles, so that I need no extra setup on my current machine.
18. As an operator, I want the printed filename to carry the version,
    so that I know which Arch release I am about to flash.
19. As an installer maintainer, I want the human and VM paths to
    resolve the same compatible ISO via one function, so that
    behavior cannot drift between them.
20. As an installer maintainer, I want VM behavior unchanged by this
    work, so that existing VM flows and tests are unaffected.
21. As an installer maintainer, I want the new tool listed in the
    CONTEXT.md Tools entry, so that the glossary stays accurate.
22. As an installer maintainer, I want the "reject latest Arch"
    decision recorded in an ADR, so that future readers do not
    re-discover the foot-gun.
23. As a test author, I want sha256 verification behind an overridable
    network seam, so that I can unit-test it without hitting the
    network.
24. As a test author, I want bats cases for match, mismatch,
    missing-line, and fetch-failure, so that the verification's
    external behavior is pinned.
25. As an operator, I want the tool to be a thin wrapper over the
    existing resolver, so that there is minimal new surface to trust.

## Implementation Decisions

- **New tool: `.os/tools/fetch-iso.sh`.** Download-only,
  non-destructive. Standalone executable matching the existing Tools
  convention (`SCRIPT_DIR`/`OS_DIR`, `set -euo pipefail`, usage
  header). Sources `lib/iso-resolver.sh` and `lib/common.sh` for
  helpers.
- **Reuses resolution logic unchanged.** Calls
  `iso_resolver_get_zfs_compatible "$OUT_DIR"`. The archzfs-supported
  kernel list and release-matching logic are not modified.
- **Dependencies self-installed.** If `jq` or `curl` are missing the
  tool runs `sudo pacman -Sy --noconfirm <missing>` (mirrors
  `pick.sh`; assumes an Arch prep machine). Only this step escalates;
  the download writes to a user-writable directory unprivileged.
- **Output directory.** Defaults to `~/Downloads`; a positional
  argument overrides. The tool `mkdir -p`s it before calling the
  resolver (which errors on a missing directory).
- **sha256 verification lives in the lib.** Add to
  `lib/iso-resolver.sh`:
  - `iso_resolver_verify_sha256 FILE` (public): derives the version
    from the filename `archlinux-<ver>-x86_64.iso`, fetches the
    release's `sha256sums.txt`, compares the file's sha256 against
    the line for that filename. Returns 0 on match; non-zero with a
    clear error (naming the file) otherwise.
  - `_iso_resolver_fetch_sha256sums VERSION` (overridable seam):
    default implementation fetches
    `https://archive.archlinux.org/iso/<ver>/sha256sums.txt`.
  Rationale: the releng JSON `sha256_sum` field is null for archived
  releases; the per-release `sha256sums.txt` is the authoritative
  source and was confirmed present for archived ISOs.
- **Tool flow.** deps → `mkdir -p` out dir → resolve → verify →
  print absolute path + flash hint. On checksum mismatch the tool
  removes the downloaded file and exits non-zero so it cannot be
  flashed.
- **Flash hint.** Prints the `dd if=… of=/dev/sdX bs=4M
  status=progress oflag=sync` one-liner and mentions
  Ventoy/Impression/Rufus as alternatives. No flashing is performed.
- **VM harness unchanged.** `_harness.sh` keeps calling
  `iso_resolver_get_zfs_compatible` and does not call the new verify
  function — VM behavior is identical to today.
- **README §2 restructure.** New §2.1 "Prepare the install media"
  (clone repo → run `tools/fetch-iso.sh` → flash) with a short
  "why not the latest Arch ISO?" note referencing the
  archzfs-Compatible ISO term. Renumber: §2.2 Boot the ISO (UEFI),
  §2.3 Connect to the internet, §2.4 Copy the scripts.
- **Glossary + ADR already written.** CONTEXT.md "archzfs-Compatible
  ISO" term and `docs/adr/0023-archzfs-compatible-iso-not-latest.md`
  exist. Remaining doc edit: append `fetch-iso.sh` to the CONTEXT.md
  Tools entry.

## Testing Decisions

- A good test asserts external behavior (exit status, emitted error
  text, chosen result), not internals, and stubs the network seam so
  it is deterministic and offline.
- **Module tested: `iso_resolver_verify_sha256`** in
  `.os/tests/iso-resolver.bats`. Prior art: existing compat tests
  stub `_iso_resolver_fetch_arch_releases` and
  `_iso_resolver_fetch_archzfs_kernels` by re-defining them after
  sourcing the module. The new tests stub `_iso_resolver_fetch_
  sha256sums` the same way.
  Cases:
  1. Checksum matches → returns 0.
  2. Checksum mismatch → non-zero, error names the file.
  3. Sums text has no line for the filename → non-zero, clear error.
  4. Sums fetch failure (seam returns non-zero) → non-zero, clear
     error.
- **`fetch-iso.sh` is made sourceable** (its `main` is guarded by
  `[[ BASH_SOURCE == $0 ]]`) so its orchestration is unit-testable —
  a new pattern for tools in this repo. `tests/fetch-iso.bats` covers:
  output-directory resolution (default `~/Downloads` and a positional
  arg, each created), checksum-mismatch cleanup (corrupt ISO removed
  + non-zero exit), and happy-path orchestration (resolver + verify
  stubbed → path + flash hint printed, file kept). Dependency
  self-install stays untested glue (stubbing `pacman`/`command -v` is
  brittle for no real signal).

## Out of Scope

- Flashing the USB (dd/Ventoy/etc.) — the tool prints a hint only.
- GPG signature verification — sha256 only; the archive is HTTPS.
- Changing the resolution logic or the archzfs source of truth.
- Wiring sha256 verification into the VM harness.
- Non-Arch prep machines — dependency self-install assumes pacman.
- Pruning or caching old ISOs beyond the resolver's existing
  reuse-if-present behavior.

## Further Notes

- Motivating incident: live ISO kernel `7.0.x` vs ZFS `2.4.2`; DKMS
  built for a mismatched kernel and `modprobe zfs` failed.
- Tool name `fetch-iso.sh` follows the verb-based Tools convention
  (`save-pkglist.sh`, `generate-configs.sh`).
- The tool exists to remove a foot-gun: by default operators reach
  for the latest ISO; the tool + README make the compatible ISO the
  obvious, blessed path.
