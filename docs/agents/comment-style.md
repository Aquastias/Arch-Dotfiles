# Comment Style

How comments are written in the installer (`.os/`). The style is compact:
say the non-obvious *why* once, anchor it to an ADR, and stop. This doc is the
convention a `docs(installer): Compact comments` pass produced and future edits
should hold to, so comments don't re-inflate.

The default is NOT "few comments". This repo deliberately documents the *why* —
subtle boot races, ZFS tuning, ADR rationale — and that is the crown jewel. The
rule is: cut what restates the code or duplicates an ADR; keep what records
reasoning found nowhere else.

## Keep

- **The genuine "why"** — reasoning not written down anywhere else: a boot race,
  a jq gotcha, why an option exists. `chroot/impermanence.sh` records the
  machine-id / logind black-screen races, `chroot/gpu.sh` each NVIDIA / AMD
  modprobe option, `zfs/pools.sh` each `-O` dataset property.
- **ADR anchors** — every `(ADR NNNN)` reference. They link code to reasoning
  and *enable* compaction: with the anchor there, the comment needn't re-argue
  the case.
- **File-header banners + the public-API listing** — agents read these first.
  Keep the one-line purpose and the `Public API:` block.
- **`# shellcheck` directives** and the `usage()` / `--help` heredocs (that is
  user-facing help, not a comment).

## Cut

- **Code restatement** — `# increment i`, `# reap background jobs` above `wait`.
  If the line says it, drop the comment.
- **ADR duplication** — prose re-explaining what an ADR already holds. Compress
  to a one-line claim + the `(ADR NNNN)` anchor.
- **Duplicated help text** — a header `USAGE:` / `OPTIONS:` block that repeats
  `usage()`; a `MODULE LOAD ORDER` list that mirrors the `source_module` calls
  below it (and drifts). Point at the canonical source instead.
- **Multi-paragraph rationale in a header** — collapse to its essential claim.
  A load-bearing failure story becomes a parenthetical carrying the same
  concrete failure modes.
- **Repeated boilerplate** — the same "on by default / derived at emit /
  idempotent" sentence on every toggle default becomes one line each.

## Mechanics

- Max 80 characters per line (repo-wide rule), comments included.
- Comment-only passes must stay comment-only: `shellcheck` + `bats` still green.

## Worked examples (from the compaction pass)

`config/layer-resolver.sh` header — a 9-line "two divergent rules" story became
a parenthetical keeping both concrete failure modes:

```
# The merge rule is per-key, not global — a global rule broke either way (core
# ["lts"] + host ["zen"] built BOTH kernels when concatenating; array-replace
# made the guided menu show a different set from what installed):
```

`packages/iso-resolver.sh` header went 60 → ~26 lines: kept every API entry,
every test seam, and the load-bearing why (the 403, the symlink scrape, the
kernel major.minor compat rule); cut the surrounding prose.
