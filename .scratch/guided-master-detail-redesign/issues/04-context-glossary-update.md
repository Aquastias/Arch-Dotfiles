# 04 — Update CONTEXT.md Guided Installer glossary to the built model

**What to build:** The **Guided Installer** glossary entry in `CONTEXT.md`
currently describes "eight top-level Configuration Categories (Host, Disks,
Options, Environment, Packages, Security, Backup, Users)". Update it to the built
model: the twelve archinstall-ordered categories (Locales, Mirrors &
Repositories, Disks, Bootloader, Kernels, System, Users, Environment, Packages,
Security, Backup, Advanced) and the always-on master-detail pane (parent column +
live detail at every level, drill-down navigation). Keep it a glossary entry —
terminology only, no implementation detail — per the domain-modeling discipline.

**Blocked by:** 01, 02, 03 — the glossary must track what actually shipped.

**Status:** ready-for-agent

- [ ] The Guided Installer entry names the twelve categories in archinstall order,
      not the old eight.
- [ ] The entry describes the always-on detail pane (parent column + live detail
      at every level) and drill-down navigation.
- [ ] The entry stays terminology-only — no file paths, function names, or
      implementation detail.
- [ ] References to the retired "Host" / "Options" categories are removed or
      corrected wherever they appear in the entry.
