# 02: Full v1 rule catalogue

**What to build:** the rest of the v1 heuristic catalogue with severity
tiers, so real incident patterns abort and common legitimate builds pass.
Critical, suspicious and info rules per PRD stories 18-30, including the
`.SRCINFO`-vs-PKGBUILD mismatch check and the source-owner vs `url=` check.
Suspicious findings abort (the allowlist comes in 04); info findings are
logged only. See ADR 0143.

**Blocked by:** 01.

**Status:** done

- [x] Critical rules: base64/xxd output into a shell or eval; network tool
      in a `.install` scriptlet; persistence writes outside `$pkgdir`;
      `source=` host that is a paste site, Discord/Telegram CDN, raw IP or
      URL shortener.
- [x] Suspicious rules: network tools in
      prepare/build/package/pkgver; `SKIP` checksums on non-VCS sources;
      source owner differs from `url=`; `.SRCINFO` mismatch; obfuscation
      markers; `http://` sources; executable top-level PKGBUILD code.
- [x] Info rules: `-bin` package; `npm ci` / cargo / go fetches.
- [x] The defanged Chaos RAT fixture (attacker `source=` patch repo) and
      the chrome-reupload fixture (`curl | python`) abort.
- [x] The benign rust and electron fixtures pass.
- [x] Every rule has at least one positive and one negative bats case.

## Comments

- 2026-09-27 audit: criteria checked against 5763ab9, 21ef008
  (tests/aur/rules.bats).
