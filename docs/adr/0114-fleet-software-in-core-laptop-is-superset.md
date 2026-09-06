# Fleet software lives in Host Core; laptop is a superset, not a subset

---
Status: accepted. **Supersedes ADR 0056's framing** ("`laptop` is a strict
*subset* of `desktop`"). The relationship is reversed and, in practice,
collapsed: desktop and laptop run the **same** software, so every app lives in
Host Core and both host profiles carry **no packages block**. Also re-triages
the user layer (User Core vs `users/aquastias`) and drops a legacy `grub`
host_program.
---

ADR 0056 moved the shared package set into Host Core on the premise that
`laptop` was a strict *subset* of `desktop` (57 repo packages in both, none
unique to laptop) — so `desktop` carried extra apps as a delta and `laptop`
carried no packages block. The operator has since clarified the fleet's actual
shape: the **laptop is a dev + gaming machine too**, wanting everything the
desktop has, plus (nominally) laptop extras. That makes laptop a *superset*, not
a subset.

Under the dedup-core rule (a thing shared by both machines belongs in core), a
laptop-superset means the *entire* desktop app set is shared and belongs in
**core** — leaving `hosts/desktop` with nothing of its own. The anticipated
"laptop extras" turned out to be already fleet-wide: **power** is the
`options.power.profile` daemon toggle, **wifi** (`iwd`) and its applet are in
core, **bluetooth** is `options.bluetooth.enabled` (+ BlueDevil /
blueman via the DE adapters), and **brightness** is powerdevil / the preset's
`brightnessctl` — all present on the desktop too (same onboard hardware).
Battery is auto-gated by the Noctalia adapter. So there are **no** laptop-only
host packages.

## Decision

**All fleet software lives in Host Core; both host profiles carry no packages
block.** `desktop` and `laptop` become identical at the package level, differing
only in per-machine facts (hostname, impermanence on/off, disk skeleton, GPU).
The former `hosts/desktop` repo + AUR packages fold into the matching Host Core
categories (adding a `virt` category); `hosts/desktop` and `hosts/laptop`
declare no `packages`.

The stray `grub` in `hosts/desktop.host_programs` is **removed**: both machines
boot `systemd-boot`, and `grub` is a [[Menu-Owned Program]] auto-injected only
when `options.bootloader = grub` (ADR 0086) — the explicit entry was legacy.

**User-layer re-triage** (a second human user is expected, so `users/core` vs a
user profile now matters):
- **`users/core`** (every real user): `virt-manager`, `searxng`, and its
  `podman` backend — `podman` precedes `searxng` so the required program
  resolves earlier in the list (ADR 0065).
- **`users/aquastias`**: `docker` (aquastias-specific) and `teamspeak3`.
- The two throwaway VM users exclude the new core set
  (`virt-manager`/`podman`/`searxng`), not the old `docker`/`virt-manager`.

## Considered options

- **Keep the ADR 0056 subset model** (desktop-delta) — rejected: it no longer
  matches the fleet; the laptop wants the same apps, so a desktop-only delta is
  wrong.
- **Minimal-base core** (apps duplicated per host profile) — rejected by the
  operator (chose dedup core); it reintroduces the duplication ADR 0056 removed.
- **Keep `grub`** as a package — rejected: dead weight on systemd-boot; it
  auto-injects if the bootloader is ever set to grub.
- **Leave `searxng`/`podman` in `users/aquastias`** — rejected: the operator
  wants them for every user, and a second user is coming, so `users/core` is now
  meaningful (previously it was cosmetic with one user).

## Consequences

- `desktop` and `laptop` are one software image + per-machine hardware — the
  cleanest expression of dedup core. Adding a package to the fleet is a one-line
  Host Core edit.
- The "desktop resolves to laptop + N packages" invariant is gone; the
  regression test now asserts the two resolve to the **same** set.
- `searxng` in `users/core` drags `podman` fleet-wide (ordered before it); VM
  fixtures exclude both to stay minimal.
- ADR 0056's rationale text (the 57/63-package counts, "strict subset") is now
  historical; CONTEXT.md's Host Core entry is updated to the superset framing.
