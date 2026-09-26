# 10: Audit + VM verify

**What to build:** an `aur-vet audit` subcommand that checks installed
foreign packages against Indicators and scans global node_modules and
npm/bun caches for campaign artefacts (atomic-lockfile, js-digest,
lockfile-js). It runs only on installer-created VMs: opt-in per VM profile
via `verify.aur_audit`, forced with `--verify-aur` (same pattern as
`--verify-boot`), and on in the desktop VM profile. It never runs on the
operator's host. See PRD stories 61-63.

**Blocked by:** 03, 06.

**Status:** ready-for-agent

- [ ] Audit exits non-zero on an Indicator hit or artefact (bats with
      fixture trees).
- [ ] VM tests parse `verify.aur_audit` and `--verify-aur`; a failed audit
      fails the VM run.
- [ ] The desktop VM profile enables it; other profiles default to off.
