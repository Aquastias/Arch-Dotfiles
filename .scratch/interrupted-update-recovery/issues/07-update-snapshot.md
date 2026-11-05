# 07: Update Snapshot

Status: done

PRD: `.scratch/interrupted-update-recovery/PRD.md`, ADR 0166.

**What to build:** on ZFS roots, every pacman transaction is preceded by an
Update Snapshot of the root, `/var` and, on Impermanence hosts, the
Rollback Datasets. `/home`, `/tmp`, `/var/cache`, `/var/log` and data
pools are excluded. The last three are kept; the snapshot taken before an
unfinished transaction is not pruned until a transaction completes.
Installed by the installer and the retrofit tool; absent on non-ZFS roots.

**Blocked by:** 02.

- [x] Bats with fake `zfs list` output: dataset selection with and
      without Impermanence
- [x] Bats: keep-three pruning; unfinished-transaction protection
- [x] Coexists with the Pacman Resnapshot Hook
- [x] Retrofit installs it on ZFS hosts only

## Comments

- Rollback Datasets are not snapshotted by the pre hook: the Rollback Hook's
  `zfs rollback -r @blank` at every boot destroys newer snapshots. Instead the
  Pacman Resnapshot Hook calls `update-snapshot.sh keep-blank`, renaming the
  pre-update `@blank` to the transaction's `@update-*` name. The retrofit
  patches an existing resnapshot helper the same way. ADR 0166 item 3 and
  the glossary updated.
- Unfinished-transaction tracking: a mark file in `/var/lib/archzfs`,
  written after the snapshot (so the snapshot never contains it) and cleared
  by a PostTransaction hook.
