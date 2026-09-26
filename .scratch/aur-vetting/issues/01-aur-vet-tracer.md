# 01: Tracer: aur-vet hook mode with a rules engine

**What to build:** a mandatory `aur-vet` command (bash + awk/coreutils only)
that, run inside an AUR git clone with `$PKGBASE` set (paru's
`PreBuildCommand` contract), reads every tracked file as text and never
sources the PKGBUILD. It runs a data-driven rule catalogue (id, severity,
scope, regex, description) through one awk engine. It prints one line per
finding (severity, rule id, file:line, description) plus a verdict line, and
exits non-zero to abort. The v1 seed has two critical rules: named
package-manager installs (`npm i <name>`, `bun add|install <name>`,
`pnpm add`, `yarn add`, `pip install <name>`, `gem install`) and a download
piped into a shell or interpreter. See PRD stories 12, 13, 17-19, 34, 53, 59,
60 and ADR 0143.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The PKGBUILD is never sourced or run through `makepkg`; a bats test
      proves top-level PKGBUILD code does not execute during vetting.
- [ ] The rules live in a data file; adding a rule needs no code change.
- [ ] The defanged Atomic Arch fixture (`npm install atomic-lockfile` in
      build or `.install`) exits non-zero with a critical finding.
- [ ] The `curl | sh` fixture exits non-zero.
- [ ] The benign electron fixture (`npm ci` / bare `npm install`) exits 0,
      with at most an info finding.
- [ ] Findings output matches the one-line format; a critical finding
      always aborts.
- [ ] The no-python guard passes.
