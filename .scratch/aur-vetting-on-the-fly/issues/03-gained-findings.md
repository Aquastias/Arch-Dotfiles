# 03: Gained findings

**What to build:** A [[Gained Finding]] — present in the package's newest
AUR commit but not in the one before — is escalated one tier (info →
suspicious, suspicious → critical), catching the "clean package plus one
injected line" attack (ADR 0149). The previous commit is read from the
clone's git objects, never checked out or sourced. A single-commit package
is scanned without comparison.

**Blocked by:** 01 (Tracer — stateless hook).

**Status:** ready-for-agent

- [ ] Two-commit fixture: a finding added in `HEAD` is escalated
- [ ] A finding in both commits keeps its tier
- [ ] Single-commit package scans normally
- [ ] Atomic Arch fixture (injected line) aborts via escalation or its own
      critical rule
