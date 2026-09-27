# 07: aur-vet seed

**What to build:** an `aur-vet seed` subcommand that collects every declared
AUR package (host `packages.aur`, DE adapter `aur` lists, User Program AUR
installs), resolves their AUR dependencies recursively via the RPC, clones
each base, and runs an interactive bulk review (findings + full files) that
writes pins on accept. See PRD story 45.

**Blocked by:** 05.

**Status:** done

- [x] Covers all three declaration sources; repo packages are excluded.
- [x] Recursive AUR dependencies are included and deduped.
- [x] Rejected packages are listed at the end; the run is resumable
      (already-pinned bases are skipped).
- [x] Bats with RPC fixtures and local clone fixtures; no real network.

## Comments

- 2026-09-27 audit: criteria checked against a7085ae, 7dbe353
  (tests/aur/seed.bats).
