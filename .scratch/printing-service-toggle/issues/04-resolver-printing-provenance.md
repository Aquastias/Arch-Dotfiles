# 04 — Resolver provenance (`source=printing`)

**What to build:** Let an operator see exactly what the Printing toggle pulls in.
The Package Resolver — which today reports no system programs at all — gains one
derived entry: when `options.printing.enabled` is on it reports `cups` with
`source=printing` and layer `derived`, using the same pure function slice 01
introduced. This flows to the guided read-only `derived` section and the
`explain-packages` CLI, giving cups the same provenance shape as Security/Backup
extras. When printing is off, cups appears nowhere in the report.

**Blocked by:** 01 — Toggle-derived cups (consumes the pure toggle→program
function).

**Status:** ready-for-agent

- [x] `explain-packages` reports `cups` with `source=printing` / layer `derived`
      when printing is on, and omits it entirely when off.
- [x] The guided read-only `derived` section lists cups under a Printing source
      when the toggle is on.
- [x] The resolver derives cups via the same pure function as the assembly
      injection (no re-derivation / drift).
- [x] Tests extend the explain-packages bats: cups reported with the printing
      source when on, absent when off (prior art: the Security/Backup derived
      assertions).
