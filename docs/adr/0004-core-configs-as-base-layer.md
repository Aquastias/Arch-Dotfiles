# ADR 0004: Core configs as base layer for hosts and users

## Status
Accepted

## Context
Multiple hosts and users share a common set of programs and settings. Without a base layer, every host and user config would duplicate those common declarations.

## Decision
Introduce a core config for each entity type: `.os/hosts/core/config.jsonc` and `.os/users/core/config.jsonc`. The runner merges core first, then applies the specific host or user config on top. Core is not optional — it is always applied.

List fields (programs, system_programs, groups) are **concatenated** — the specific config adds to core, never replaces it. Scalar fields (shell, sudo) in the specific config override core.

## Consequences
- Common system programs go in host core; host-specific ones go in the host config
- Common user programs and shell defaults go in user core; user-specific ones go in the user config
- `hosts/core/` and `users/core/` are reserved directory names — no real host or user may be named `core`
- Merge order is deterministic: core lists + specific config lists, deduped; specific scalars win over core scalars
