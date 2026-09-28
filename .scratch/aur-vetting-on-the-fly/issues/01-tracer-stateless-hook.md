# 01: Tracer — stateless hook

**What to build:** [[AUR Vetting]] decides every build on the spot (ADR
0149). In hook mode `aur-vet` no longer reads or writes pins: a package that
is unpinned or has changed builds when its scan is clean; a critical finding
aborts; a suspicious finding asks `n` (abort) / `y` (accept once) / `a`
(accept always for this package + rule, written to the root-owned
allowlist) and aborts when unattended. Existing allowlist rows become
package + rule. The bump-only engine and the maintainer-pin rules go.

**Blocked by:** None (can start immediately).

**Status:** done

- [x] Hook passes a clean unpinned package and a clean changed package with
      no pin store present
- [x] Critical aborts; suspicious prompts n/y/a; unattended suspicious aborts
- [x] `a` appends `pkgbase rule note` to the root-owned allowlist; the row
      applies to a later commit of that package
- [x] Allowlist format drops the commit column; repo rows converted
- [x] bump-only engine, `trust-maintainer-changed`,
      `trust-maintainer-unrecorded` removed
- [x] Pins bats rewritten as stateless cases; incident fixtures abort,
      benign fixtures pass
