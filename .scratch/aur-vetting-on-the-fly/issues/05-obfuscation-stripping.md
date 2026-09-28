# 05: Obfuscation stripping

**What to build:** Rules match a normalised twin of each scanned line —
empty quote pairs removed, single-character quoting and backslash-letter
escapes collapsed, `${IFS…}` turned into a space — so quote-splitting can't
dodge them (ADR 0149). Findings still report the original line.

**Blocked by:** None (can start immediately).

**Status:** done

- [x] Rule-case rows: `cu""rl … | sh`, `'c'url … | sh`, `c\url … | sh`,
      `curl${IFS}…|sh` fire pipe-to-shell
- [x] Negative rows: ordinary quoted strings don't create false findings
- [x] Reported text is the original line
- [x] Existing rule cases stay green
