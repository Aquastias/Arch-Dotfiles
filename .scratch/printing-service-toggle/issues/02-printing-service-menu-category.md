# 02 — Printing service menu category (Cycle Field)

**What to build:** A dedicated, discoverable **Printing service** switch in the
Guided Installer. A new root-level Configuration Category (a peer of
Security/Backup, not folded into General) holds exactly one field bound to
`options.printing.enabled`. Because its option set is exactly `{true,false}`, it
renders as a Cycle Field: Enter flips it in place on the category screen with no
drill-in, and the `●` override dot shows only when the operator diverges from the
default (on). The detail pane lists both values with the current one marked.

**Blocked by:** 01 — Toggle-derived cups (needs the schema key to bind the row).

**Status:** ready-for-agent

- [x] A root-level **Printing service** category appears in the top-level menu in
      canonical reading order, with a one-line summary.
- [x] Its single field is bound to `options.printing.enabled` and behaves as a
      Cycle Field (flips in place, no values submenu).
- [x] The field shows no override dot at the default (on) and a `●` dot when set
      to off; flipping back to on clears the override.
- [x] The category/field preview reflects live state (both values listed, current
      marked).
- [x] Tests extend the guided-menu bats: the category and its Cycle Field render
      with correct default and override-dot behaviour.
