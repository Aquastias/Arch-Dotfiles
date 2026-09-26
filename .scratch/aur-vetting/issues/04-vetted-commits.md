# 04: Vetted Commits

**What to build:** pin each package base to a Vetted Commit in one repo pin
file (pkgbase, commit, maintainer, date, note), readable from an
overridable store path.
- An unpinned package aborts when unattended. When interactive it gets a
  full review of all files plus findings, and is pinned on accept.
- A newer HEAD is vetted as a diff against the pin. Bump-only diffs (every
  changed line is `pkgver`/`pkgrel`/checksum in PKGBUILD/`.SRCINFO`, no
  other file changed) are auto-accepted with a logged pin bump. Any other
  diff prompts when interactive and aborts when unattended.
- A suspicious-finding allowlist is scoped to (pkgbase, Vetted Commit).

Unattended is detected by the absence of a TTY or the installer's
unattended signal. There is no bypass flag. See PRD stories 35, 37-44, 50.

**Blocked by:** 01.

**Status:** done

- [ ] Unpinned + unattended exits non-zero with a clear message.
- [ ] Unpinned + interactive accept writes a pin row.
- [ ] A bump-only diff auto-accepts and bumps the pin; a diff adding one
      extra line aborts when unattended.
- [ ] An allowlisted suspicious finding passes at its commit and fails
      again on a new commit.
- [ ] No `AUR_VET=off` / `--no-vet` path exists (a bats test asserts that
      both are rejected or ignored).
