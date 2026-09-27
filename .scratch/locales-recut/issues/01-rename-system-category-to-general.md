# 01 — Rename System category to General

**What to build:** The Guided Installer Configuration Category that holds a
machine's hostname and timezone is presented as **General** instead of
**System**. Its contents, position in the archinstall-reading-order list, and
behaviour are unchanged — only the category name moves. Timezone is not relocated
into Locales and does not get its own category. Independent of all locale work.

**Blocked by:** None — can start immediately.

**Status:** done

- [x] The category holding `hostname` and `timezone` renders as **General** in
      the top-level category list and its preview.
- [x] No category named **System** appears anywhere in the menu surface.
- [x] **General** keeps the slot **System** held in the category order.
- [x] The **General Category** glossary term (CONTEXT.md) and ADR 0076 remain
      consistent with the shipped name.
- [x] Menu/category tests assert the **General** name and the absence of
      **System**. Prior art: `tests/config/guided-menu.bats`.

## Comments

- 2026-09-27 audit: 8be14fb. Later reversed: ADR 0081 renamed the category back
  to System (GENERAL became the bucket name, ADR 0086).
