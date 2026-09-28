# 04: Adoption from the AUR's own data

**What to build:** Probable adoption is read from the AUR RPC, never from
git authors (spoofed in Atomic Arch): `Maintainer ≠ Submitter` and
`LastModified` within 14 days, for every package. Suspicious alone;
critical together with a [[Gained Finding]] (ADR 0149).

**Blocked by:** 03 (Gained findings).

**Status:** ready-for-agent

- [ ] RPC fixture: recent adoption alone → suspicious
- [ ] Recent adoption + gained finding → critical
- [ ] Old adoption (> 14 days) → no adoption finding
- [ ] No trust decision reads git author/committer
