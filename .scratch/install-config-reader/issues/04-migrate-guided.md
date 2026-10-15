# 04: Move the Guided Installer onto the reader

**What to build:** the Guided Installer (~77 reads, controller screens included)
read the Effective Config only through the Install Config Reader — bound to
JSON where the module holds JSON — with no raw `// <default>` jq reads of
config paths. Behaviour unchanged. Fields missing from the schema get a row
here. The raw-read lint baseline shrinks by every migrated read. Decisions:
candidate #1, Q17 (expand–contract batch).

**Blocked by:** 01, 02, 03

**Status:** done

- [x] No raw config reads left in this scope
- [x] Lint baseline entries for this scope removed
- [x] Scope's existing tests green; full suite green

## Comments

2026-10-15: 20 lint-flagged reads (lint scoped to schema-owned fields) moved
to bound accessors (`$(install_config_use_json …; install_config_<name>)`) or,
inside jq programs, `--argjson defaults "$(install_config_default_object …)"`
+ `// $defaults.<path>`. `encryption_enabled` read via `install_config_get`
(the special forces false under manual; raw semantics kept). Two
`raw-config-ok`: a data pool object's `.filesystem`, the "(unnamed host)"
label. Edge: kernel count for an explicit `[]` is now 1 (lts, as install
reads it), was 0. Guided + config/guided-* suites green.

Follow-ups not flagged by the lint (restated defaults via a jq variable
holding a sub-object): `_controller_swap_label` (`$o.swap_size`, zswap
on/compressor), `_controller_layout_graph` `rpool`. Possible bug: the
pool-filesystem cycle starts from "zfs" for a data pool with no filesystem,
though it inherits the root's (ADR 0043).

2026-10-15 (code review): call sites read through
`install_config_from_json <json> <accessor>` (one helper instead of ~25
hand-rolled `$(install_config_use_json …; …)`). `get` bypasses of a special
(`encryption_enabled`, `impermanence_enabled`, `kernels`) carry a one-line
why. `_controller_profile_tree` keeps `--argjson defaults` (the jq-program
pattern of ADR 0154) rather than six separate binds in a preview path.
