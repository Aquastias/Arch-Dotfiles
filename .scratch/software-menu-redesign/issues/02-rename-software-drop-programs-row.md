# 02 — Rename Packages → Software, drop the Programs row

**What to build:** The Guided Installer's software [[Configuration Category]] is
renamed from **Packages** to **Software** and drills only `repo`, `aur`, and
`derived`. The `host programs` field row is removed from the menu model, since
every host program is now Menu-Owned and has no home here (ADR 0086). The
existing `repo` / `aur` / `derived` drill and the three-state provenance dots
are unchanged. From the operator's view: the category reads **Software** with
summary `repo, aur, derived`, and no Programs row appears.

**Blocked by:** None — can start immediately. (Its rationale rests on ticket 01,
but it lands green on its own.)

**Status:** done

- [x] `menu_categories` carries a **Software** category (not Packages) with
      summary `repo, aur, derived`, in the same SOFTWARE bucket position.
- [x] `menu_rows` no longer emits a `host programs` field row.
- [x] The `repo` / `aur` / `derived` drill and provenance dots are unaffected.
- [x] Any category-name reference used for navigation is updated so drilling
      Software still reaches its children.
- [x] Covered in `guided-menu.bats`, following the existing category/row tests.
