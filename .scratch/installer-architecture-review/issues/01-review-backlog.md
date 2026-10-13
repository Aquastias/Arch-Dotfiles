# 01: Installer architecture review — deepening backlog

**What to build:** nothing directly — the backlog from the 2026-10-13
`/improve-codebase-architecture` review of `.installer/` (hot spots: config,
guided, feature-audit, layout, packages, profiles, matrix, vm). Each
candidate below gets its own grilled ticket when picked. Live drifts it found
are fixed in `.scratch/installer-drift-fixes/`.

Agreed order: #1 → #2 → #3 → #4; #5–#8 untriaged.

**Blocked by:** None

**Status:** needs-triage

## Candidates

1. **Install Config Reader over any Effective Config** (Strong, in-process).
   Schema (`lib/config/install-config.sh`) reads only the `CONFIG_FILE`
   global, so JSON-holding modules re-encode path + default: 59 inline
   `// default` jq reads across 22 files (package-resolver, gate,
   controller-*, vm.sh ×10). 22 defaults duplicated in `menu.sh`
   `_MENU_FIELDS`; `.options.swap_size` has no schema row (raw ×3). Two jq
   restatements added by the drift fixes (`_package_resolver_filesystem_sets`
   LUKS rule, `feature_audit_any_zfs`) — the second already missed storage
   groups once. Deepen: reader takes file or JSON, owns every path + default;
   menu/seed derive from it. Extends ADR 0015.
2. **One Package composition for install + Package Resolver** (Strong,
   in-process). `package-list.sh` and `package-resolver.sh` share leaf tables
   but each decides which sets apply (LUKS drift fixed; "any zfs" still
   written twice). Deepen: one composition; install consumes it, the query
   reports it with provenance; test install = report. ADR 0043, 0058.
3. **One "validate this Effective Config" entry point** (Strong,
   local-substitutable). Three hand-rolled copies (`03-install.sh`
   `load_configuration`, `feature_audit_validate_config`, matrix-assembly
   `_matrix_validate_cell`): CONFIG_FILE export, ~11 ordered sources,
   lifecycle load/detect, adapter by kind, disk probe stub. Deepen: one entry
   point; block-device probe is the only seam. ADR 0014, 0046, 0048.
4. **Program Selection as one pure step** (Strong, in-process). Selection
   lives in `runner_run_profiles` locals shared by dynamic scope (37 refs);
   recomputed in gate.sh, validation-programs.sh:37, profile-loader.sh:406.
   Gate omits secrets-activated sops (needs install-state). Tests grep
   runner source for call order (`profiles-gpg-quiesce.bats:65-68`). Deepen:
   Effective Config + secrets flag → ordered host + per-user sets.
   ADR 0025, 0041, 0065, 0152.
5. **Layout Record as data behind accessors** (Worth exploring). Adapters
   redefine same function names on source; `LAYOUT_*` globals read raw in
   8–11 files each; `state.sh` wraps only `_LAYOUT_IMPL_*`. ~30 files /
   3,477 lines. ADR 0016, 0034, 0043.
6. **Config Store owns all Guided session files** (Worth exploring). Store
   covers 3 of 16 `GUIDED_*_FILE`s; 16 silent-no-op `[[ -n … ]] ||` guards;
   hand stash/restore in `controller-enter-host.sh:86-126`; 19 test files
   set the globals. ADR 0042, 0049, 0051.
7. **Install State writer generated from its schema** (Worth exploring).
   `lib/install-state.sh` declares the field list 3× (schema, jq template,
   `--arg`s); `apparmor` missing from the schema, read raw in
   `lib/boot/lsm.sh:16`. ADR 0015, 0018.
8. **VM Harness owns repo source + file server** (Speculative).
   `serve-http.sh` lifecycle owned in 4 places (flow-test, flow-persistent,
   matrix/run.sh race workaround); gateway URL check duplicated;
   `matrix_cell_profile` is a pass-through. ADR 0032, 0046.

## Comments
