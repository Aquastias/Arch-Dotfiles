# ADR 0149: AUR Vetting on the fly, without Vetted Commits

## Status
Accepted — pending implementation. Supersedes ADR 0143's Vetted Commits (the
pin store, bump-only auto-accept, `repin`/`seed`/`export`, the
maintainer-changed rule). Keeps ADR 0143's seams (paru `PreBuildCommand`,
bootstrap rung, yay refusal), text-only analysis, rules-as-data, Indicators,
severity tiers, no-bypass and root-owned install. Research:
`.scratch/aur-vetting-on-the-fly/research.md`.

## Context
Vetted Commits made every non-bump change of every AUR package a manual
review, and an unattended install aborts on the first unreviewed one (the
VSCodium VM run died on `ccusage`). The operator wants a package verified
when it is installed or upgraded, not re-approved on every change. The pin's
real value was two signals: "the maintainer changed" and "this commit added
something new". Both can be recomputed at build time without stored state.

## Decision
- **Stateless:** every build scans the package as it is now — the current
  clone, its previous commit and the AUR RPC — and decides there. No pin
  store; nothing to re-vet later.
- **Outcome:** *critical* always aborts. *suspicious* asks at a terminal,
  aborts unattended. *info* is logged.
- **Allowlist per package + rule, no commit:** an accepted suspicious rule
  for a package stays accepted across its updates (`allow.tsv` loses its
  commit column).
- **Handover from the AUR RPC, never git:** git author/committer is
  attacker-set (Atomic Arch spoofed it). `Maintainer ≠ Submitter` with a
  recent `LastModified` marks a probable adoption: *suspicious* alone,
  *critical* together with a gained finding.
- **Gained risk:** `HEAD` and `HEAD~1` are both scanned; a finding only
  `HEAD` has is escalated one tier (suspicious → critical, info →
  suspicious) — the Atomic Arch shape of a clean package plus one line.
- **Normalise before matching:** quote-splitting (`cu""rl`, `'c'url`) and
  `${IFS…}` are stripped from a copy of each line before the rules run.
- **Wider rules** from the research: credential access, exfiltration,
  reverse shells, privilege/tamper (sudo in functions, SUID, sudoers/doas,
  PAM, `setcap`, `SigLevel`, keyring, CA trust, security off), rootkit/kernel
  (`insmod`/`modprobe`, `/sys/fs/bpf`, `LD_PRELOAD`, `ld.so.preload`),
  miners, metadata tricks (provides/replaces/conflicts core or security
  packages, `epoch`, `install=`/`backup=` misuse, weak or missing
  checksums), evasion (`/tmp` exec, `nohup`/`setsid`, here-string exec,
  `printf` assembly) and repo oddities (scripts behind media/library
  extensions, editor auto-exec files, hidden `.install`, missing files).
- **Removed:** `vetted.tsv`, `aur-vet seed`/`export`/`repin`, the root pin
  store `/etc/aur-vet/vetted.tsv`, `bump-only.awk`, and the rules
  `trust-maintainer-changed` / `trust-maintainer-unrecorded`.

## Considered Options
- **Auto-accept clean diffs, keep pins** — still a state file and a review
  queue; rejected as the annoyance the operator named.
- **Trust on first use (auto-pin)** — same state, weaker first look;
  rejected.
- **Handover from git history** — spoofable; rejected for the RPC.
- **LLM review (manticore/aurscan)** — network + non-determinism in an
  unattended installer; rejected.

## Consequences
- No review queue: updates build as soon as their scan is clean.
- Lost: a human look at a change the rules don't recognise, and an exact
  maintainer-transfer signal (the RPC has no ownership history, so adoption
  stays approximate). Accepted: the rules cover both real attacks, and the
  gained-risk escalation targets the injected-line pattern.
- Legitimately adopted packages cost one confirmation when they also gain a
  finding; an allowlisted rule never asks again for that package.
