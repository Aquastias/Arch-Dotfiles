# 01: Grub ESP auto = 1G

**What to build:** A grub install with esp_size auto resolves to 1G, so it
clears the absolute 1G floor (ADR 0038) and installs. Fixes jsonl F001, F002
(grub). Amends ADR 0078.

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] esp-budget.bats: grub auto = 1G; floor still rejects <1G for all loaders
- [ ] check.bats: every manifest variant validates
- [ ] ADR 0078 amended
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (grub)

## Comments

Grub auto ESP = 1G floor (c7fbe4b); ADR 0078 amended.

**2026-10-04 — superseded** by GRUB booting from the ESP (ticket 27
comments, ADR 0078 amendment 2026-10-04): grub now uses the per-kernel ESP
budget like every loader; the 1G rule is gone.
