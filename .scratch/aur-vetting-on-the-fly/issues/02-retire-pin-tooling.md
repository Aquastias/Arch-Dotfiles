# 02: Retire the pin tooling

**What to build:** Nothing in the repo or on an installed system suggests
pins still matter (ADR 0149). `vetted.tsv`, `aur-vet seed` and
`aur-vet repin` are deleted; `aur-vet export` only merges/checks the
allowlist; the [[Runner]] stops seeding a pin store while still installing
the vetter, rules, Indicators and allowlist root-owned. Help text, comments
and the [[AUR Helper]] notes drop pin wording.

**Blocked by:** 01 (Tracer — stateless hook).

**Status:** done

- [x] `vetted.tsv`, `seed`, `repin` and their tests removed
- [x] `export` / `export --check` cover the allowlist only, tested
- [x] Profiles AUR-vet bats: no pin store seeded; vetter + data + allowlist
      root-owned; hook present; yay refusal intact
- [x] No remaining pin references outside ADR 0143 history
