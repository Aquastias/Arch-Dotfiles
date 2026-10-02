# 14: KDE bind scenes Meta+K/D/7

**What to build:** Scenes start krusader before Meta+K and set up windows /
task-manager entries before Meta+D and Meta+7. Fixes F876-F878.

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (desktop)

## Comments

Meta+7-9 launch extra apps, Show Desktop judged by screen, per-bind settle
(8a39393, 6d463ab); Meta+K is a raise under Wayland → screen-changes
(8300f82).
