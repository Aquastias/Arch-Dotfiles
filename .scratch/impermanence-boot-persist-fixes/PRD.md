# PRD: Impermanence boot-visible persists + sops/impermanence VM (retroactive)

Status: done

Retroactive record — shipped without a grill session. Anchored by
[[ADR 0144]] (Persist Mount units in `/usr/lib`; `/root` not rolled back),
amending [[ADR 0008]] / [[ADR 0044]].

## What shipped

- New VM `desktop/combined-sops-impermanence` (sops secrets +
  impermanence on the combined desktop).
- Persist Extension units + `wants` links live under `/usr/lib` so PID 1 sees
  them at boot; `/root` dropped from Rollback Datasets and persisted.
- VM: `@blank` baked after vm-agent autologin edits on impermanence guests.
- Host/user secrets found under the `vm/` fallback (after users moved to
  `users/vm/`).
- clamav signatures seeded at install so clamd starts on first boot.

## Commits

0a16530, ea195b8, 96a5a48, d07e97e, 1eaebf7, 6697173.
