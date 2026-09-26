# AUR Vetting

Status: ready-for-agent

Decision of record: **ADR 0143** (AUR Vetting via Vetted Commits), amending
ADR 0052 (AUR Helper ladder; installs now refused under the `yay` rung).
Builds on ADR 0041 (Primary User's paru pass) and ADR 0036 (Effective Config).

Glossary touched (`CONTEXT.md`): **AUR Vetting**, **Vetted Commit**,
**Indicator** (all new).

## Problem Statement

The AUR has been hit by repeated supply-chain attacks. In July 2025, Chaos
RAT arrived through a `source=` entry pointing at an attacker's git repo, and
a reuploaded `google-chrome-stable` ran a `curl | python` one-liner. In June
2026, the Atomic Arch campaign hit about 1,500 orphaned packages: attackers
adopted them and injected `npm install atomic-lockfile` (or `js-digest`,
`lockfile-js`, `bun install`) without touching upstream code.

The operator's installer builds AUR code unattended under `--noconfirm` in
four places:
- the AUR Helper bootstrap rungs;
- the Runner's `packages.aur` / adapter `aur` pass;
- User Program install scripts;
- the booted pkglist tool.

Daily `paru -Syu` builds AUR code too. None of these paths reviews anything,
so a hijacked package, or a hijacked dependency of a declared package,
reaches root during an install or update with no warning.

## Solution

Every AUR package base (including AUR dependencies, recursively) passes
**AUR Vetting** before it is built, on every build path. Vetting reads the
package's AUR git repo as text only and never executes it. It reports three
kinds of finding:
- **Indicator** matches (known-bad markers from past incidents);
- heuristic red flags from a data-driven rule catalogue;
- trust signals from the AUR RPC (maintainer change, orphan adoption, age).

Each reviewed package is pinned to a **Vetted Commit**. A later commit is
vetted as a diff. A pure version bump by the same maintainer is
auto-accepted. Anything else needs an explicit review and accept, and it
aborts outright when unattended.

paru calls the vetter through `PreBuildCommand` before any build. The
bootstrap rungs call it directly. Under `yay`, AUR installs are refused.
There is no bypass. Vetting guarantees nothing about fetched sources or
`-bin` payloads; it catches red flags and changes of trust.

## User Stories

1. As the operator, I want every AUR package vetted before it builds, so
   that a hijacked PKGBUILD never reaches my system silently.
2. As the operator, I want AUR dependencies vetted recursively, so that a
   clean top-level package can't pull in a compromised AUR dependency.
3. As the operator, I want the AUR Helper bootstrap packages (`paru`,
   `paru-bin`, `yay-bin`) vetted before `makepkg`, so that the very first
   AUR build is guarded too.
4. As the operator, I want the Runner's single paru pass vetted, so that
   host `packages.aur` and DE adapter `aur` lists are covered.
5. As the operator, I want User Program installs through the AUR Helper
   vetted, so that per-program AUR packages are covered.
6. As the operator, I want the booted pkglist tool vetted, so that restoring
   a package list is guarded.
7. As the operator, I want my daily `paru -S` / `-Syu` vetted, so that
   updates to orphaned or hijacked packages are caught (the Atomic Arch
   vector).
8. As the operator, I want vetting to run as paru's `PreBuildCommand`, so
   that one hook covers every paru path with no wrapper to remember.
9. As the operator, I want the hook set in both the system paru.conf and
   each user's paru.conf, so that a per-user config can't silently drop it.
10. As the operator, I want any failed vetting to abort the whole paru
    transaction, so that nothing is half-installed.
11. As the operator, I want AUR installs refused under `yay`, with a clear
    "vetting needs paru" message, so that the fallback helper never becomes
    an unguarded path.
12. As the operator, I want the PKGBUILD never sourced or run through
    `makepkg --printsrcinfo` during vetting, so that the review itself can't
    execute attacker code.
13. As the operator, I want every file in the AUR repo scanned (PKGBUILD,
    `.install` scriptlets, patches, local scripts, `.SRCINFO`), so that a
    payload hidden outside the PKGBUILD is caught.
14. As the operator, I want a `.SRCINFO` that doesn't match its PKGBUILD
    reported as suspicious, so that a URL hidden from the metadata surfaces.
15. As the operator, I want known-bad Indicators (package names, npm names,
    domains, hashes, paths) matched, so that known campaign artefacts are
    caught at once.
16. As the operator, I want a package-name Indicator to be critical only for
    commits inside the campaign window, and suspicious until pinned
    otherwise, so that cleaned-up packages aren't blocked forever.
17. As the operator, I want named package-manager installs (`npm i <name>`,
    `bun add`, `pnpm add`, `yarn add`, `pip install <name>`, `gem install`)
    flagged critical, so that Atomic Arch-style injection is blocked.
18. As the operator, I want lockfile-driven installs (`npm ci`, bare
    `npm install`) and cargo/go fetches reported only as info, so that
    legitimate electron/rust/go builds pass.
19. As the operator, I want a download piped into a shell or interpreter
    flagged critical, so that `curl | sh`-style droppers are blocked.
20. As the operator, I want decoded blobs (`base64 -d`, `xxd -r`) fed into a
    shell or `eval` flagged critical, so that obfuscated payloads are
    blocked.
21. As the operator, I want any network tool in a `.install` scriptlet
    flagged critical, so that post-install droppers running as root are
    blocked.
22. As the operator, I want writes to `~/.ssh`, shell rc files, cron,
    `/etc/profile.d` or systemd user units outside `$pkgdir` flagged
    critical, so that persistence attempts are blocked.
23. As the operator, I want `source=` hosts that are paste sites,
    Discord/Telegram CDNs, raw IPs or URL shorteners flagged critical, so
    that attacker-hosted payloads are blocked.
24. As the operator, I want network tools inside
    `prepare`/`build`/`package`/`pkgver` flagged suspicious, so that fetches
    outside `source=` get my review.
25. As the operator, I want `SKIP` checksums on non-VCS sources flagged
    suspicious, so that unverified downloads get my review.
26. As the operator, I want a `source=` owner that differs from the `url=`
    project flagged suspicious, so that a Chaos RAT-style "patch repo" is
    surfaced.
27. As the operator, I want obfuscation markers (long base64/hex blobs,
    heavy `\x` escapes, `rev`, `printf %b` into eval) flagged suspicious, so
    that hidden logic gets my review.
28. As the operator, I want `http://` sources flagged suspicious, so that
    downloads that can be tampered with in transit are noticed.
29. As the operator, I want executable top-level PKGBUILD code beyond plain
    assignments flagged suspicious, so that code running at parse time is
    noticed.
30. As the operator, I want `-bin` packages reported as info, so that I
    know the payload is opaque to static review.
31. As the operator, I want a maintainer different from the one recorded
    with the Vetted Commit flagged critical, so that takeovers are blocked.
32. As the operator, I want orphan adoption and first submission under 14
    days ago flagged suspicious, so that new or freshly adopted packages get
    my review.
33. As the operator, I want out-of-date and low-vote packages reported as
    info, so that I have context without being blocked.
34. As the operator, I want critical findings to always abort, so that the
    worst signals can't be clicked through by mistake.
35. As the operator, I want suspicious findings to abort unless allowlisted
    for that package and Vetted Commit, so that a reviewed exception doesn't
    carry over to a new commit.
36. As the operator, I want info findings logged but not blocking, so that
    context is kept without noise.
37. As the operator, I want each package pinned to a Vetted Commit (with
    the maintainer at pin time), so that any later change is detectable.
38. As the operator, I want pins stored in one repo file, so that I can
    grep them, diff them and follow them in `git log`.
39. As the operator, I want a newer HEAD vetted as a diff against the
    Vetted Commit, so that I only review what changed.
40. As the operator, I want diffs that only touch `pkgver`, `pkgrel` or
    checksums (in both PKGBUILD and `.SRCINFO`), by the same maintainer,
    auto-accepted with a logged pin bump, so that routine updates don't
    nag me.
41. As the operator, I want any other diff to prompt me with the findings
    and the diff, so that I decide on real changes.
42. As the operator, I want an unattended install to abort on any
    non-bump diff, so that nothing unreviewed builds while I'm away.
43. As the operator, I want an unpinned package to abort an unattended
    install, so that the installer only builds what I've reviewed.
44. As the operator, I want an unpinned package in interactive use to get a
    full review of all files plus findings, pinned on accept, so that I can
    adopt new packages safely.
45. As the operator, I want `aur-vet seed` to walk every declared AUR
    package and its AUR dependencies for a one-time bulk review, so that I
    can populate pins before the first vetted install.
46. As the operator, I want the booted pin store owned by root and seeded
    from the repo at install, so that user-level malware can't forge pins.
47. As the operator, I want accepts on a booted system to need sudo, so
    that pin writes are privileged.
48. As the operator, I want `aur-vet export` to write the booted store back
    into the repo, so that I can commit pins accepted in daily use.
49. As the operator, I want a guard that flags drift between the repo pin
    file and the store seeded at install, so that the two can't silently
    diverge.
50. As the operator, I want no `AUR_VET=off` / `--no-vet` bypass, so that
    neither malware nor muscle memory can switch vetting off.
51. As the operator, I want the RPC retried with backoff and then aborted
    when unattended, so that a transient blip doesn't skip trust signals.
52. As the operator, I want an interactive prompt to continue without
    trust signals when the RPC is down, so that I can still work offline
    knowingly.
53. As the operator, I want rules kept as data (id, severity, scope, regex,
    description), so that the next incident is a data change, not a code
    change.
54. As the operator, I want Indicators kept in the repo, each line tagged
    with its source, so that every entry is traceable and there is no live
    third-party dependency at runtime.
55. As the operator, I want Indicators drawn from primary sources first
    (the official Arch list, advisories), with community lists (lenucksi)
    only filling gaps, so that the data is trustworthy.
56. As the operator, I want an optional refresh command that pulls
    community lists into the repo for review, so that updating Indicators
    is easy but never automatic.
57. As the operator, I want the vetter to be a mandatory core installer
    component, not a toggleable Program, so that it exists in the chroot
    before the bootstrap rung and can't be deselected.
58. As the operator, I want the vetter installed as a PATH command with its
    data installed system-wide on every host, so that every user's paru hook
    works whether or not a dotfiles clone exists.
59. As the operator, I want the vetter written in bash plus awk/coreutils
    only, so that it respects the No Python rule.
60. As the operator, I want each finding printed with rule id, severity,
    file, line and description, so that I can judge it quickly.
61. As the operator, I want `aur-vet audit` to scan installed foreign
    packages against Indicators and look for campaign npm/bun artefacts, so
    that test VMs prove they came out clean.
62. As the operator, I want audit opt-in per VM profile (`verify.aur_audit`)
    and forced with `--verify-aur`, and on in the desktop profile, so that
    it follows the existing `verify.*` pattern.
63. As the operator, I want audit never run on my host, so that the tool
    stays within installer-created VMs.
64. As a future maintainer, I want defanged fixtures reproducing each real
    incident, so that I can prove the rules still catch them.
65. As a future maintainer, I want benign real-world fixtures, so that
    false positives are caught before they block installs.

## Implementation Decisions

- **Vetter module (new, deep):** one command, `aur-vet`, with a narrow
  interface:
  - Default mode (the hook) reads the current directory (an AUR git clone)
    and `$PKGBASE`. It exits 0 to pass and non-zero to abort, with findings
    on stderr. This matches paru's `PreBuildCommand` contract: run via
    `sh -c` per package base after all downloads and before any build,
    inside the clone directory; non-zero aborts the whole transaction,
    even under `--noconfirm` (verified in paru source).
  - Subcommands: `seed`, `export`, `audit`, and the Indicator refresh.
  - Unattended vs interactive is decided by whether a TTY is present, plus
    the installer's existing unattended signal. Unattended never prompts.
- **Analysis engine:** text only. awk/grep over every tracked file in the
  clone. Sources come from `.SRCINFO` and are cross-checked against the
  PKGBUILD text. The PKGBUILD is never sourced or run.
- **Rule catalogue:** tab-separated data (`id`, `severity`
  critical|suspicious|info, `scope` file/function/source, `regex`,
  `description`), run by one awk engine. v1 rule set as listed in user
  stories 17 to 30.
- **Indicator store:** tab-separated data (`kind`
  pkgbase|npm|domain|sha256|path, `value`, `campaign`, `window`, `source`).
  Package-name Indicators are windowed by campaign dates.
- **Trust signals:** one AUR RPC `info` query per package base. Maintainer
  and submitter are compared with the pin; orphan adoption and first
  submission are checked against 14 days. RPC failures retry with backoff
  (ADR 0052 pattern).
- **Pin store:** tab-separated (`pkgbase`, `commit`, `maintainer`, `date`,
  `note`). The repo file is the source of truth. The installer seeds a
  root-owned system copy; accepts write there with sudo; `export` writes
  back. Suspicious-finding allowlist entries are scoped to
  (pkgbase, Vetted Commit).
- **Bump-only classifier:** a diff between the Vetted Commit and HEAD is
  bump-only when every changed line in PKGBUILD/`.SRCINFO` is a `pkgver`,
  `pkgrel` or checksum assignment and no other file changed.
- **Recursive dependencies:** under paru, the hook fires for every AUR base
  in the transaction, so recursion comes for free. `seed` resolves the AUR
  dependency tree itself through the RPC.
- **Runner changes:**
  - The bootstrap rung calls the vetter between `git clone` and `makepkg`.
  - The AUR install path refuses to run when the landed helper is `yay`.
  - The vetter, its data and the seeded store are staged self-contained
    into the chroot before bootstrap (like the AUR Helper resolution lib;
    no Installer Stdlib inside the chroot).
- **paru.conf:** a system `/etc/paru.conf` edit plus a per-user
  `paru.conf` dotfile, both carrying `PreBuildCommand`.
- **VM verify:** a new optional `verify.aur_audit` key and a `--verify-aur`
  flag in the VM tooling, run after a clean test install; on in the desktop
  VM profile.
- **Messaging:** one line per finding: severity, rule id,
  file:line, description. A summary verdict line follows. The yay refusal
  prints an actionable message.

## Testing Decisions

- Good tests assert external behaviour only: exit code and findings output
  for a given clone, pin store, data and RPC fixture. They never assert
  internal function calls or intermediate files.
- **Primary seam: the `aur-vet` command as a black box.** Bats tests build
  fixture AUR clones as real git repos. RPC answers come from a fixture
  JSON selected by an environment override, and the clock is overridable
  for the window and age rules. Coverage:
  - defanged Atomic Arch, Chaos RAT and chrome-reupload fixtures (must
    abort);
  - benign electron (`npm ci`) and rust fixtures (must pass);
  - bump-only diffs (auto-accept);
  - non-bump diffs (abort when unattended);
  - maintainer change (critical);
  - `.SRCINFO` mismatch (suspicious);
  - unpinned package when unattended (abort);
  - allowlisted suspicious finding (pass, but fails again on a new commit);
  - RPC down (retry, then abort when unattended);
  - the `seed`, `export` and `audit` subcommands.
- **Runner seam (existing):** extend the AUR bootstrap and AUR install bats
  suites. They check that the rung calls the vetter before `makepkg`, that
  a vetter failure fails the rung, that AUR installs are refused under yay,
  and that the vetter is staged into the chroot.
- **Config guards (existing pattern):** both paru.conf files carry the
  hook; the repo pin file and the seeded store don't drift.
- **VM seam (existing):** VM-mode tests cover `verify.aur_audit` and
  `--verify-aur` parsing. The real audit runs in live VM runs.
- **Prior art:** the AUR helper and bootstrap bats suites (stubbed chroot,
  shadowed `sleep` for retry timing), the pkglist tool bats, the no-python
  guard, and the drift guard from the recent Claude settings sync fix.
- paru itself is not exercised in unit tests. Its hook contract is pinned
  by the vetter seam plus the source-verified fact in ADR 0143.

## Out of Scope

- Sandboxed or network-isolated builds and filesystem-diff analysis.
- Inspecting fetched upstream sources or `-bin` payloads (opaque by design).
- Catching a compromised upstream tarball behind a bump-only diff.
- Vetting under `yay` (refused, not guarded).
- A pre-pass resolver for non-paru helpers.
- Running `aur-vet audit` on the operator's host.
- Live runtime fetches of community Indicator lists.
- Any bypass flag or environment toggle.
- Python tooling, including running lenucksi's `aur-malware-check`.

## Further Notes

- Research sources: the aur-general Atomic Arch master thread and the
  official list on `md.archlinux.org`; the aur-general firefox-patch-bin
  advisory; BleepingComputer (Chaos RAT); Linuxiac (google-chrome-stable);
  StepSecurity and Privacy Guides (Atomic Arch); lenucksi/aur-malware-check
  (GPL-3; data only, as a cross-check).
- By design, daily `-Syu` gets noisier. The bump-only auto-accept is the
  pressure valve.
- Landing on the `yay` rung after a transient paru failure blocks AUR
  installs for that run. That's accepted.

## Addendum: repin + doctor (ticket 11)

Decided after the first implementation pass:

66. As the operator, I want `sudo aur-vet repin <pkgbase>` to accept a
    legit maintainer transfer after reviewing the transition and the diff
    and typing the new maintainer's name, so that a takeover can't be
    waved through by a habitual `y`, yet real transfers aren't stuck.
67. As the operator, I want a login warning when any paru.conf that
    overrides `/etc/paru.conf` lacks the hook, so that AUR builds never
    silently run unvetted.
