# 02 — Always-on master-detail pane: parent column + simple-field detail

**What to build:** Wherever the operator's cursor sits in the Guided Installer,
the preview pane shows the archinstall master-detail view: the **parent column**
(every sibling listed, greyed, the current item marked) above a **live detail**
of the highlighted item. A category previews a `key: value` summary of its fields
with `●` override dots; a leaf field previews its current value plus its allowed
option set (or short help for free-text). The Mirrors & Repositories detail states
that the selected countries drive reflector's mirror ranking
(`reflector --country <list> --latest 10 --sort rate`) — a display string only.

The preview pane is made **always-on**: the previous per-screen gate (which
populated the pane only on the Disk-layout screen) is retired, and the pane shows
at a fixed width at every depth. Navigation is unchanged drill-down (Enter deeper,
Esc up); the persistent parent column is realised by this render, not a second
live cursor (true Miller was rejected in ADR 0071). The render is a pure function
so it is testable headlessly, like the existing layout-graph / breadcrumb builders.

Look target: prototype Variant A + C's persistent column
(`.scratch/guided-master-detail-redesign/prototype.html`) — clean archinstall
chrome, no card/footer clutter.

**Blocked by:** 01 — the parent-column siblings and the reflector-note placement
follow the final twelve-category taxonomy.

**Status:** ready-for-agent

- [ ] The preview pane is populated on every category and every field screen (no
      screen falls back to a hidden/empty pane).
- [ ] Highlighting an item renders its sibling set as a parent column, greyed,
      with the current item marked.
- [ ] A category previews a `key: value` summary of its fields with `●` dots on
      overridden fields.
- [ ] A leaf field previews its current value and, for an enumerable field, the
      `menu_enum_options` set; a free-text field previews its value + short help.
- [ ] The Mirrors & Repositories detail includes the reflector note; no reflector
      behaviour or field path changes.
- [ ] The render is a pure function driven by (state, nav location) with no tty.
- [ ] A new headless bats suite (styled on the existing `_ctl_layout_graph` /
      `_ctl_breadcrumb` tests) asserts the parent column, category detail, leaf
      value+options, and the reflector note — and passes.
