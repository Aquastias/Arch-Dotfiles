# 01 — Re-curate KDE app roster: `apps_list` + `apps_extra`

**What to build:** Selecting KDE installs the operator's authoritative
app set. The KDE adapter config carries the re-curated `apps_list`
(packages whose pacman `Groups` contains `kde-applications`, plus the
three plasma-group no-ops `spectacle`/`plasma-systemmonitor`/`discover`
that `plasma-meta` already pulls) and a new sibling `apps_extra` section
for KDE-ecosystem repo packages outside that group (`krita`, `digikam`,
`okteta`, `kommit`, `krename`, `krusader`, `kdiff3`). `haruna` and
`merkuro` are added, each routed to `apps_list` vs `apps_extra` by its
actual pacman group at build time. Dead/redundant entries are pruned:
`karbon` (⊂ calligra), `kclock`, `skanlite`, `arianna`, `kgpg`,
`kompare`, and the unrequested `keditbookmarks`. The adapter installs
both sections in one pacman pass; the Package Resolver reports them as
derived sources so `explain-packages` and the Guided `derived` view stay
accurate. Both sections are deselectable in the Guided Installer.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `apps_extra` is a sibling Categorized-List section
      (`{ category: { pkg: bool } }`) beside `apps_list`, parsed in bool
      mode by the Categorized List Parser
- [ ] `apps_list` holds only group members plus the three documented
      plasma-meta no-ops; every non-group KDE app lives in `apps_extra`
      (ADR 0087)
- [ ] `haruna`/`merkuro` are placed by verified pacman group, not a
      pre-assumed one
- [ ] Pruned entries (`karbon`, `kclock`, `skanlite`, `arianna`,
      `kgpg`, `kompare`, `keditbookmarks`) appear in no section
- [ ] The adapter installs `apps_extra` alongside `apps_list`; a
      malformed section aborts with a pathed parser error
- [ ] The Package Resolver emits `kde-apps` and `kde-apps-extra`
      (layer `derived`, category `Environment`)
- [ ] `kde-adapter.bats`: the shipped-jsonc regression lock is rewritten
      to the new `apps_list` roster, with a sibling lock on `apps_extra`
      membership and a lock that the pruned entries appear nowhere
- [ ] The adapter's `aur` block is unchanged (repo-only guarantee holds)
