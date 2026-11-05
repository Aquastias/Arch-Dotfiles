# 05: Battery preflight

Status: done

PRD: `.scratch/interrupted-update-recovery/PRD.md`, ADR 0166.

**What to build:** a kernel transaction is refused, with a clear message,
when the machine runs on battery below 30% and is not charging. No battery
means no check; non-kernel transactions are never blocked. Installed by the
installer and the retrofit tool.

**Blocked by:** 02.

- [x] Bats with a fake power-supply tree: absent, charging, discharging
      above and below 30%, non-kernel transaction
- [x] Refusal aborts the transaction before any file changes
- [x] Retrofit installs it
