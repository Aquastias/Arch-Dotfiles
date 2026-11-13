# 18: Contract: strict everywhere

**What to build:** ADR 0167 holds across the whole repo with no
transition aid. The Migrated Areas list is removed, so every new rule is
strict everywhere. The `parent_directory` / `base_name` helpers are
deleted from every Commons world (Installer Stdlib, chroot common, Shell
Stdlib) now that no caller remains. ADR 0167's status becomes
"implemented".

**Blocked by:** 04, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15, 16, 17

**Status:** ready-for-agent

- [x] Migrated Areas mechanism and its tests removed
- [x] Strict Readability Lint passes on the whole repo
- [x] Path helpers deleted; no reference left outside ADRs/`.scratch/`
- [x] Full bats suite (`-j 4` max) and audit pass
- [x] One final VM install passes
- [x] ADR 0167 status set to implemented
