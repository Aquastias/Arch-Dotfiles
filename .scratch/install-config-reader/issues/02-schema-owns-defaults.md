# 02: Schema owns every config default; menu and seed derive from it

**What to build:** the Install Config schema declares path, type and default
for every Effective Config field anyone reads — adding rows for fields it
lacks today (e.g. `options.swap_size`, `options.pacman.*`, `post_install.*`,
`sysctl`). Guided menu field rows keep only section + label and name their
schema row; the guided seed defaults come from the schema. A default lives in
exactly one place. Decisions: candidate #1, Q16.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Every menu field resolves its default from a schema row
- [ ] Seed defaults derive from the schema
- [ ] Test: no default declared outside the schema
- [ ] Guided menu renders identically (existing guided suite green)

## Comments
