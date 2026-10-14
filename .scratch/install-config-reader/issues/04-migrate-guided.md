# 04: Move the Guided Installer onto the reader

**What to build:** the Guided Installer (~77 reads, controller screens included)
read the Effective Config only through the Install Config Reader — bound to
JSON where the module holds JSON — with no raw `// <default>` jq reads of
config paths. Behaviour unchanged. Fields missing from the schema get a row
here. The raw-read lint baseline shrinks by every migrated read. Decisions:
candidate #1, Q17 (expand–contract batch).

**Blocked by:** 01, 02, 03

**Status:** ready-for-agent

- [ ] No raw config reads left in this scope
- [ ] Lint baseline entries for this scope removed
- [ ] Scope's existing tests green; full suite green

## Comments
