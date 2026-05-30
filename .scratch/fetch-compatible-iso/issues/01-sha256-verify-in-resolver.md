Status: ready-for-agent

# 01 — sha256 verification in the resolver lib

## Parent

`.scratch/fetch-compatible-iso/PRD.md`

## What to build

Add ISO checksum verification to the ISO resolver as a deep,
isolated-testable capability, behind an overridable network seam (the
same pattern the resolver already uses for its other network calls).

End-to-end behavior: given a downloaded Arch ISO file, verify its
sha256 against Arch's authoritative published checksum for that
release, returning success only on an exact match and a clear,
file-naming error otherwise.

- A public verification entry point takes an ISO file path, derives
  the Arch version from its `archlinux-<ver>-x86_64.iso` filename,
  obtains the release's `sha256sums.txt`, and compares the file's
  sha256 against the line for that filename.
- The network fetch of the sums file is a separate, overridable
  function so tests can stub it. Its default implementation reads the
  release's `sha256sums.txt` from `archive.archlinux.org`.
- Rationale (already settled in the PRD/ADR 0023): the releng JSON
  `sha256_sum` field is null for archived releases, so the per-release
  `sha256sums.txt` is the source of truth.

VM harness behavior must be unchanged — this only adds functions; no
existing caller invokes verification.

## Acceptance criteria

- [ ] A public `iso_resolver_verify_sha256`-style function exists in
      the resolver lib and returns 0 only when the file's sha256
      matches the published sum for its filename.
- [ ] The sums-file fetch is an overridable seam (default: archive
      `sha256sums.txt`); no other resolver behavior changes.
- [ ] On mismatch, missing line, or fetch failure the function exits
      non-zero with a clear message that names the file.
- [ ] `iso-resolver.bats` gains 4 cases, stubbing the fetch seam the
      same way existing compat tests stub
      `_iso_resolver_fetch_arch_releases`:
      match → 0; mismatch → error names file; no line for filename →
      error; sums fetch failure → error.
- [ ] Existing resolver tests and VM-harness behavior are unaffected.

## Blocked by

None - can start immediately.
