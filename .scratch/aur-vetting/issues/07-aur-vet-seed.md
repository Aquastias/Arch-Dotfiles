# 07: aur-vet seed

**What to build:** an `aur-vet seed` subcommand that collects every declared
AUR package (host `packages.aur`, DE adapter `aur` lists, User Program AUR
installs), resolves their AUR dependencies recursively via the RPC, clones
each base, and runs an interactive bulk review (findings + full files) that
writes pins on accept. See PRD story 45.

**Blocked by:** 05.

**Status:** ready-for-agent

- [ ] Covers all three declaration sources; repo packages are excluded.
- [ ] Recursive AUR dependencies are included and deduped.
- [ ] Rejected packages are listed at the end; the run is resumable
      (already-pinned bases are skipped).
- [ ] Bats with RPC fixtures and local clone fixtures; no real network.
