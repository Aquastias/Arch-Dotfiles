# 01: Stow opt-in (prefactor)

**What to build:** `./stow-configs.sh` with no arguments skips any Program
marked **opt-in**; naming it explicitly still stows it. Prefactor for
[[VSCodium Config]] (ADR 0148) so a host's own VSCodium is never adopted into
or overwritten by the repo. Extends the pure stow-selection logic with an
opt-in set (empty in this ticket's fixtures); install-time Config Apply is
unaffected.

**Blocked by:** None (can start immediately).

**Status:** done

- [x] Pure selection takes an opt-in set: opt-in names dropped from the
      no-arg selection
- [x] Opt-in names kept when passed positionally; `--except` behaviour
      unchanged
- [x] config-apply bats covers all three cases; existing cases stay green
- [x] Wrapper usage text documents the opt-in rule
