# Spec: AUR Vetting on the fly (no Vetted Commits)

Status: ready-for-agent

Anchors: ADR 0149 (this decision), ADR 0143 (AUR Vetting; its seams, rules
engine and no-bypass stand), ADR 0052 (AUR Helper ladder). Research:
`.scratch/aur-vetting-on-the-fly/research.md`. Glossary: [[AUR Vetting]],
[[Gained Finding]], [[Indicator]], [[AUR Helper]], [[Runner]].

## Problem Statement

Every AUR package change that is more than a version bump needs a manual
review and a new pin before it may build. Daily upgrades stall on reviews,
and an unattended install aborts on the first unreviewed change — the
VSCodium VM install died because `ccusage` had changed. The operator wants a
package checked at the moment it is installed or upgraded, and nothing to
re-approve afterwards. At the same time the checks must still catch the real
attacks (Atomic Arch, CHAOS RAT) and should cover the red flags other
scanners and analysts report, several of which the rules miss today.

## Solution

AUR Vetting becomes stateless. Each time paru (or the installer's bootstrap
rung) is about to build an AUR package, `aur-vet` scans that package as it
is: the current clone, its previous commit, and the AUR server's metadata. A
clean scan builds; a critical finding aborts; a suspicious finding asks at a
terminal (once, or always for this package) and aborts when unattended. No
pins exist. Two signals the pins used to provide are recomputed live: a
[[Gained Finding]] (the newest commit added something the previous commit
lacked) is escalated, and a probable adoption is read from the AUR server's
Maintainer/Submitter/LastModified — never from spoofable git authors. Rule
coverage grows to the categories the research found missing, and obfuscated
spellings (`cu""rl`, `${IFS}`) are normalised before matching.

## User Stories

1. As the operator, I want an AUR package checked when I install it, so that
   I never keep a review queue of pins.
2. As the operator, I want an AUR upgrade checked when it builds, so that a
   changed package needs no separate re-approval.
3. As the operator, I want a clean package to build without any prompt, so
   that routine installs and upgrades just work.
4. As the operator, I want an unattended install to finish when every AUR
   package scans clean, so that a changed-but-clean package like `ccusage`
   no longer aborts a VM or fresh install.
5. As the operator, I want a critical finding to always abort the build, so
   that a known-bad pattern can never be waved through.
6. As the operator, I want a suspicious finding shown with its rule, file,
   line and text, so that I can judge it quickly.
7. As the operator, I want to answer a suspicious finding with "no", "yes
   once" or "yes, always for this package", so that I choose how much to
   trust it.
8. As the operator, I want an "always" answer remembered for that package and
   rule across future versions, so that an accepted quirk (e.g. `vscodium-bin`
   running code at parse time) never asks again.
9. As the operator, I want an "always" answer to be stored root-owned, so
   that user-level malware cannot add allowlist entries.
10. As the operator, I want `aur-vet export` to merge accepted allowlist
    entries back into the repo, so that my next install inherits them.
11. As the operator, I want a suspicious finding to abort an unattended run,
    so that nothing questionable builds without a human.
12. As the operator, I want the existing allowlist rows converted to
    package + rule entries, so that nothing I accepted before asks again.
13. As the operator, I want a finding that only the newest AUR commit has to
    be escalated one tier, so that the "clean package plus one injected
    line" attack stands out.
14. As the operator, I want a finding present in both the newest and the
    previous commit left at its normal tier, so that long-standing quirks
    are not escalated on every update.
15. As the operator, I want a package with a single commit scanned without a
    gained-finding comparison, so that brand-new packages still work.
16. As the operator, I want probable adoption detected from the AUR server's
    Maintainer, Submitter and LastModified, so that spoofed git authors
    cannot hide a takeover.
17. As the operator, I want probable adoption alone to be suspicious and
    critical when combined with a gained finding, so that legitimate
    adoptions cost at most one confirmation while Atomic Arch-style
    takeovers abort.
18. As the operator, I want the adoption window to stay 14 days since the
    last modification, so that the signal matches the existing trust rule.
19. As the operator, I want `cu""rl`, `'c'url`, `c\url` and `${IFS}` tricks
    normalised before rules run, so that quote-splitting cannot dodge them.
20. As the operator, I want credential access flagged (`~/.ssh`, GPG,
    keyrings, browser profiles, cloud/CI credential files, environment
    dumps), so that stealers are caught.
21. As the operator, I want exfiltration flagged (HTTP POST/upload of files,
    `nc` transfers, Discord/Telegram/Slack webhooks, DNS exfil), so that
    data leaving the machine is caught.
22. As the operator, I want reverse shells flagged (`nc -e`, `socat`,
    `mkfifo` pipes, python/perl/ruby socket shells, `/dev/tcp`), so that
    remote-control payloads are caught.
23. As the operator, I want privilege and tampering flagged (`sudo` inside
    package functions, SUID/SGID bits, sudoers/doas edits, PAM changes,
    `setcap`, pacman `SigLevel` downgrades, `pacman-key` trust changes, CA
    trust injection, disabling AppArmor/firewall), so that system takeovers
    are caught.
24. As the operator, I want rootkit and kernel tricks flagged
    (`insmod`/`modprobe`, `/sys/fs/bpf`, `LD_PRELOAD`, `/etc/ld.so.preload`),
    so that the Atomic Arch eBPF payload class is caught.
25. As the operator, I want cryptominers flagged (`xmrig`, `stratum+tcp://`,
    wallet addresses), so that miners are caught.
26. As the operator, I want metadata tricks flagged (provides/replaces/
    conflicts a core or security package, `epoch`, `install=` pointing
    outside the repo, `backup=` of a security-sensitive file, MD5/SHA1-only
    or missing checksums), so that impersonation and forced upgrades are
    caught.
27. As the operator, I want evasion flagged (executing from `/tmp`,
    `nohup`/`setsid`/`disown` detaching, here-string execution, `printf`
    command assembly), so that staged payloads are caught.
28. As the operator, I want repo oddities flagged (script content behind a
    media or library extension, editor auto-exec files like `.envrc` or
    `.vscode/tasks.json`, dot-prefixed `.install`, `install=`/`source=` files
    missing from the repo), so that hidden payloads are caught.
29. As the operator, I want every new rule to be data in the rules table, so
    that it is reviewable and extendable without code.
30. As the operator, I want the benign packages (an electron app using
    `npm ci`, a rust app, the Host Core AUR set) to still pass, so that the
    wider rules do not drown me in prompts.
31. As the operator, I want the real-incident fixtures (Atomic Arch
    PKGBUILD and `.install` variants, CHAOS RAT, the Chrome re-upload) to
    still abort without any pins, so that the known attacks stay covered.
32. As the operator, I want the Indicator lists and campaign windows kept, so
    that known-bad names, domains and hashes still abort.
33. As the operator, I want no bypass flag, so that "on the fly" never means
    "off".
34. As the operator, I want the installer to stop seeding a pin store and
    keep installing the vetter, rules, Indicators and allowlist root-owned,
    so that booted systems behave the same way.
35. As the operator, I want `aur-vet seed` and `aur-vet repin` gone, and
    `vetted.tsv` deleted from the repo, so that nothing suggests pins still
    matter.
36. As the operator, I want `aur-vet audit` and `aur-vet doctor` to keep
    working, so that VM audits and the login hook check are unaffected.
37. As the operator, I want the yay fallback to still refuse AUR builds, so
    that nothing is built unvetted.
38. As the operator, I want AUR RPC outages handled as today (retry, then
    abort unattended / ask interactively), so that trust signals are not
    silently skipped.
39. As a maintainer, I want the glossary and ADR 0143/0149 to match what
    shipped, so that the next change starts from the truth.

## Implementation Decisions

- **Vetter command (`aur-vet`)**: hook mode no longer reads or writes a pin
  store. Decision per build = rules over the clone + gained-finding
  comparison + RPC trust rules + Indicators + allowlist. Exit codes stay
  (0 pass, 1 abort, 2 usage/environment).
- **Gained finding**: the rules engine runs on the working tree of `HEAD`
  and of `HEAD~1` (materialised from the clone's git objects, never by
  checking out or sourcing). A finding keyed by rule + normalised matched
  text present only in `HEAD` is escalated one tier (info → suspicious,
  suspicious → critical). No `HEAD~1` → no comparison.
- **Probable adoption**: `trust-adopted` applies to every package (not only
  unpinned ones): `Maintainer ≠ Submitter` and `LastModified` within 14
  days → suspicious; with any gained finding → critical. Git author and
  committer are never used for trust.
- **Normalisation**: before regex matching, each scanned line gets a
  normalised twin — empty quote pairs removed, single-character quoting and
  backslash-letter escapes collapsed, `${IFS…}` replaced by a space. Rules
  match the twin; findings report the original line.
- **Rules table**: new rules land as rows in the rules data with id,
  severity, scope, regex, description, following ADR 0143's format and the
  80-column continuation convention. Categories per story 20–28. Severity
  guideline: credential access, exfiltration, reverse shells, rootkit/kernel,
  miners, sudoers/PAM/SigLevel/keyring/CA tampering → critical; metadata
  tricks, evasion, repo oddities, `setcap`, weak checksums → suspicious;
  informational signals → info.
- **Allowlist**: rows become `pkgbase rule note` (commit column dropped);
  existing rows are converted, not re-reviewed. Interactive answers:
  `n` abort, `y` accept once (nothing stored), `a` accept always (append to
  the root-owned store via sudo). `aur-vet export` merges the root store's
  allowlist into the repo copy; `export --check` flags drift.
- **Removed**: pin store (repo and root), `seed`, `repin`, bump-only
  engine, `trust-maintainer-changed`, `trust-maintainer-unrecorded`, and the
  runner's pin seeding. Help text, comments and the AUR Helper notes that
  mention pins are updated.
- **Unchanged**: paru `PreBuildCommand` seam, bootstrap-rung call, yay
  refusal, text-only analysis (PKGBUILD never sourced), root-owned install
  under `/usr/local`, override lockdown (`AUR_VET_UNATTENDED` only refuses
  prompts), RPC retry policy, Indicators and campaign windows, `audit`,
  `doctor`.

## Testing Decisions

- Good tests drive `aur-vet` exactly as paru does (hook mode, fixture clone,
  RPC fixture) and assert only exit status and reported findings — never
  internal awk state.
- **Hook seam** (existing aur-vet/trust/pins bats, pins rewritten as
  "stateless" cases): clean passes with no store; critical aborts;
  suspicious prompts (y once / a always / n) and aborts unattended; an
  "always" row applies at a later commit; gained finding escalates (fixture
  with two commits); unchanged finding does not; single-commit package
  scans; adoption suspicious alone, critical with a gained finding.
- **Rule-case table** (rules bats + rule-cases data): ≥1 positive and ≥1
  negative row per new rule, plus normalisation rows (`cu""rl … | sh`,
  `${IFS}` spacing) that must fire.
- **Incident + benign fixtures**: Atomic Arch (PKGBUILD and `.install`),
  CHAOS RAT, Chrome re-upload abort with no pins; electron/rust/benign-dep
  pass.
- **Installer wiring** (profiles AUR-vet bats): no pin store seeded; vetter,
  data and allowlist still installed root-owned; hook present; yay refusal.
- **Removed suites**: seed, repin; export narrows to allowlist merge/check.
- **Full suite + shellcheck + no-python** green (known pre-existing failures
  excepted); one VM install (`arch-combined`, local repo) proves an
  unattended install completes with the current AUR set.

## Out of Scope

- Sandboxed builds, network isolation during `makepkg`.
- LLM or remote threat-intel lookups (VirusTotal, URLhaus) at build time.
- A full shell parser; normalisation stays awk-level.
- Binary/ELF inspection of `-bin` payloads.
- Changes to the Indicator refresh flow.

## Further Notes

- ADR 0149 was amended during spec writing: `aur-vet export` survives for the
  allowlist (story 10), since "always" answers land in the root store.
- The research flags that static review misses novel or heavily obfuscated
  attacks and opaque `-bin` payloads; that limit is inherited from ADR 0143.
