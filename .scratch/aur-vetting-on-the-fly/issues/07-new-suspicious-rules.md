# 07: New suspicious rules (+ tamper criticals)

**What to build:** The remaining research categories: privilege/tamper
(`sudo` in package functions, SUID/SGID, `setcap` → suspicious; sudoers/
doas, PAM, `SigLevel` downgrade, `pacman-key` trust, CA trust injection,
disabling AppArmor/firewall → critical), metadata tricks (provides/
replaces/conflicts a core or security package, `epoch`, `install=` outside
the repo, `backup=` of a sensitive file, MD5/SHA1-only or missing
checksums), evasion (`/tmp` exec, `nohup`/`setsid`/`disown`, here-string
exec, `printf` assembly) and repo oddities (script behind a media/library
extension, editor auto-exec files, dot-prefixed `.install`, missing
`install=`/`source=` files). File-level checks live in the engine as
builtins.

**Blocked by:** 05 (Obfuscation stripping).

**Status:** ready-for-agent

- [ ] ≥1 positive and ≥1 negative case per new rule (rule-case rows or
      fixture cases for builtins)
- [ ] Severity per the spec's guideline
- [ ] Benign fixtures still pass
