# 01 — Core-Owned Program filter (prefactor)

**What to build:** A new `Core-Owned Program` concept — a `kind: host` Program
whose sole home is Host Core (unconditional base), never presented in a Guided
Installer program picker. Introduce a `core_owned_programs()` set (empty at this
stage) and have both program pickers subtract it *alongside* the existing
`menu_owned_programs`, so a later slice enrolls a Program by adding one name to
the set rather than touching picker internals. This lands with zero observable
behaviour change (an empty set filters nothing) and unblocks the promotions.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `core_owned_programs()` exists in the menu-owned module, returns nothing
      yet, and is documented as "sole home is Host Core" (parallel to
      `menu_owned_programs`).
- [ ] Both `_ctl_host_program_names` and `_ctl_user_program_names` subtract
      `core_owned_programs` in addition to `menu_owned_programs`.
- [ ] `menu_owned_programs` stays semantically control-owned — its existing
      union test (`guided-controller.bats`) is unchanged.
- [ ] The Guided host `host_programs` menu row stays absent (ADR 0086);
      `guided-menu.bats` still passes with no new host-programs row.
- [ ] `CONTEXT.md` gains a `Core-Owned Program` glossary term, and the existing
      "every `kind: host` program is Menu-Owned" statement is corrected to
      "Menu-Owned *or* Core-Owned".
- [ ] Full bats suite green (no behaviour change expected).
