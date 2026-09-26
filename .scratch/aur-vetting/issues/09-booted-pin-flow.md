# 09: Booted pin flow

**What to build:** on a booted system, interactive accepts write the
root-owned pin store through sudo. `aur-vet export` writes the store back
into the repo pin file for the operator to commit. A drift guard flags
divergence between the repo pin file and the seeded store. See PRD
stories 46-49.

**Blocked by:** 06.

**Status:** ready-for-agent

- [ ] An accept without sudo fails cleanly; with sudo it writes the store.
- [ ] `export` produces a repo-file diff containing only the new or changed
      rows.
- [ ] The drift guard fails when the repo file and the seeded store
      diverge.
