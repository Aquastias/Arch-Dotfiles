# 07: Update Snapshot

Status: ready-for-agent

PRD: `.scratch/interrupted-update-recovery/PRD.md`, ADR 0166.

**What to build:** on ZFS roots, every pacman transaction is preceded by an
Update Snapshot of the root, `/var` and, on Impermanence hosts, the
Rollback Datasets. `/home`, `/tmp`, `/var/cache`, `/var/log` and data
pools are excluded. The last three are kept; the snapshot taken before an
unfinished transaction is not pruned until a transaction completes.
Installed by the installer and the retrofit tool; absent on non-ZFS roots.

**Blocked by:** 02.

- [ ] Bats with fake `zfs list` output: dataset selection with and
      without Impermanence
- [ ] Bats: keep-three pruning; unfinished-transaction protection
- [ ] Coexists with the Pacman Resnapshot Hook
- [ ] Retrofit installs it on ZFS hosts only
