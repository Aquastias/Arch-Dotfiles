Status: done

# 02 — fetch-iso.sh tool (end-to-end)

## Parent

`.scratch/fetch-compatible-iso/PRD.md`

## What to build

A new tool, `.os/tools/fetch-iso.sh`, that an operator runs on their
current machine (this dotfiles repo, on Arch) to obtain the ISO the
installer can actually build ZFS against — before booting anything.
Download-only and non-destructive; the operator flashes the USB
themselves.

End-to-end behavior:

1. If `jq`/`curl` are missing, install them via
   `sudo pacman -Sy --noconfirm`. Only this step escalates; the rest
   runs unprivileged.
2. Resolve and download the newest archzfs-Compatible ISO via the
   existing `iso_resolver_get_zfs_compatible`, into `~/Downloads` by
   default or a directory given as a positional argument (created if
   missing). An already-present ISO is reused, not re-downloaded.
3. Verify the download's sha256 using the verification function from
   issue 01. On mismatch, remove the corrupt file and exit non-zero
   so it cannot be flashed.
4. On success, print the absolute ISO path (filename carries the
   version) plus a one-line flash hint: the `dd … of=/dev/sdX bs=4M
   status=progress oflag=sync` command, and a mention of
   Ventoy/Impression/Rufus as alternatives.

Follow the existing Tools convention (standalone executable,
`SCRIPT_DIR`/`OS_DIR`, `set -euo pipefail`, usage header). Resolver
errors (no archzfs kernels / no matching archived ISO) surface
clearly to the operator.

## Acceptance criteria

- [ ] `.os/tools/fetch-iso.sh` runs end-to-end and leaves a verified
      compatible ISO in `~/Downloads` (default) or the given dir.
- [ ] Missing `jq`/`curl` are installed via `sudo pacman -Sy`; the
      download itself runs without root.
- [ ] Output directory defaults to `~/Downloads`, is overridable by a
      positional arg, and is created if absent.
- [ ] sha256 mismatch removes the file and exits non-zero with a
      clear message; success prints the absolute path + flash hint
      (dd one-liner + Ventoy/Impression/Rufus mention).
- [ ] No flashing is performed; resolver failures surface with clear
      errors.
- [ ] VM harness behavior is unchanged.
- [ ] The tool is sourceable (`main` guarded by `BASH_SOURCE == $0`)
      and `tests/fetch-iso.bats` covers output-dir resolution
      (default + arg), checksum-mismatch cleanup, and happy-path
      orchestration with the resolver/verify functions stubbed.

## Blocked by

- Issue 01 (sha256 verification in the resolver lib).
