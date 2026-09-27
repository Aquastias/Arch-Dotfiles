# 09: Booted pin flow

**What to build:** on a booted system, interactive accepts write the
root-owned pin store through sudo. `aur-vet export` writes the store back
into the repo pin file for the operator to commit. A drift guard flags
divergence between the repo pin file and the seeded store. See PRD
stories 46-49.

**Blocked by:** 06.

**Status:** done

- [x] An accept without sudo fails cleanly; with sudo it writes the store.
- [x] `export` produces a repo-file diff containing only the new or changed
      rows.
- [x] The drift guard fails when the repo file and the seeded store
      diverge.

## Comments

- 2026-09-27 audit: criteria checked against 11984fb (tests/aur/export.bats).
