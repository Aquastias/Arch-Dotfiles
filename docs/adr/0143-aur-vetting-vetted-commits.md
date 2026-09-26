# ADR 0143: AUR Vetting via Vetted Commits

## Status
Accepted — implemented (`.installer/aur/`). Adds the [[AUR Vetting]],
[[Vetted Commit]] and [[Indicator]] terms to `CONTEXT.md`. Amends ADR 0052:
the `yay` fallback rung still bootstraps, but AUR builds refuse to run under
it.

## Context
The AUR was hit twice in a year. In July 2025, Chaos RAT came in through a
`source=` entry pointing at an attacker repo, and a reuploaded
`google-chrome-stable` ran `curl | python`. In June 2026, Atomic Arch hit about
1,500 packages: attackers adopted orphaned packages and added
`npm install atomic-lockfile` (or `js-digest`, `lockfile-js`, `bun install`) to
existing packages without changing upstream code. The installer builds AUR
code unattended (`--noconfirm`) in four places: the AUR Helper bootstrap
rungs, the Runner's `packages.aur` pass, User Program `install.sh` scripts,
and `tools/install-pkglist.sh`. Daily `paru -Syu` builds AUR code too. None of
these paths is reviewed. Static review can never prove a package safe,
because fetched sources and `-bin` blobs stay opaque. The goal is to catch
red flags and changes of trust, not to certify safety.

## Decision
- **Every AUR package base is vetted before it is built**, and AUR
  dependencies recursively, on every build path. The checks are Indicator
  matches, heuristic rules, and AUR RPC trust signals. There is no sandboxed
  build.
- **Vetted Commits pin the reviewed AUR git commit** for each package base.
  Pins live in one repo file, `.installer/aur/vetted.tsv`
  (`pkgbase commit maintainer date note`). A newer HEAD is vetted as a diff.
  A diff that only touches `pkgver`, `pkgrel` or checksums, with the same
  maintainer, is auto-accepted and the pin is bumped. Any other diff prompts,
  or aborts when unattended. An unpinned package aborts the installer. When
  interactive, it gets a full review and is pinned on accept. `aur-vet seed`
  bulk-reviews the declared set once.
- **Seams:**
  - paru `PreBuildCommand = aur-vet`, set in both `/etc/paru.conf` and each
    user's `paru.conf`, with a bats guard. paru runs it once per base, after
    all downloads and before any build (verified in paru source:
    `install.rs`, `exec.rs`). A non-zero exit aborts the whole transaction,
    even under `--noconfirm`.
  - The bootstrap rung calls the vetter between `git clone` and `makepkg`.
  - Under `yay`, which has no hook, AUR installs abort with "vetting needs
    paru". A pre-pass would race yay's own re-clone.
- **Text-only analysis:** the PKGBUILD is never sourced and never passed to
  `makepkg --printsrcinfo`, because both would execute attacker code. The
  vetter uses awk/grep over every repo file and takes sources from
  `.SRCINFO`. A `.SRCINFO` that doesn't match the PKGBUILD is a finding.
- **Rules are data:** `rules.tsv` (`id severity scope regex description`) and
  `indicators.tsv`, run by an awk engine and bash only (no Python, so
  community tools like `aur-malware-check` supply data, not code). The
  Indicator list is kept in the repo. An optional refresh pulls in community
  lists for review, never live at runtime.
- **Indicator sources:** primary sources first. Package names come from the
  official Arch list (the aur-general thread / `md.archlinux.org`); npm names,
  domains, hashes and paths come from the advisories. lenucksi's `iocs.txt`
  fills gaps, and every line is tagged with its source.
- **Package-name Indicators:** *critical* only when the commit falls inside
  the campaign window (Atomic Arch: 2026-06-09 to 06-14). Otherwise
  *suspicious* until pinned, so a cleaned package isn't blocked forever.
  Payload rules catch a re-infection.
- **Severity tiers:**
  - *critical* always aborts.
  - *suspicious* aborts unless the finding is allowlisted for that package
    and Vetted Commit.
  - *info* is logged.

  The key critical signals:
  - a named package install (`npm i <name>`, `bun add`, `pip install
    <name>`); lockfile installs such as `npm ci` are only info;
  - downloading a script and piping it into a shell;
  - network calls in `.install` scriptlets;
  - a maintainer who differs from the one recorded with the Vetted Commit.
- **Delivery:** a core installer component, not a Program, and not
  toggleable. It is staged into the chroot self-contained, like
  `aur-helper.sh`. It installs as `/usr/local/bin/aur-vet`, with data in
  `/usr/local/share/aur-vet/`. The booted pin store is
  `/etc/aur-vet/vetted.tsv`,
  owned by root and seeded from the repo, so user-level malware can't forge
  pins. `aur-vet export` writes it back to the repo, and a bats guard catches
  drift.
- **No bypass:** there is no `AUR_VET=off` or `--no-vet`. The only escape is an
  explicit accept, which leaves a pin behind.
- **RPC unreachable:** the installer retries (ADR 0052 pattern) and then
  aborts. When interactive, it asks whether to continue without trust signals.
- **Tests:** bats with defanged fixtures of each real incident, plus benign
  PKGBUILDs (an electron app using `npm ci`, a rust app) to catch false
  positives.

## Considered Options
- **Sandboxed build** (network namespace, filesystem diff): rejected. It's
  heavy, and cutting network breaks legitimate cargo, go and npm builds.
- **Warn-only:** rejected. Warnings are useless in an unattended install.
- **Auto-accepting any clean diff:** rejected in favour of bump-only diffs,
  because a heuristic-clean diff can still add logic.
- **A Host Program:** rejected. It would load after the bootstrap rung, and a
  toggle would defeat the point.

## Consequences
- Every new AUR package, and every non-bump update, needs a manual review
  and a pin before it builds. Daily `-Syu` gets noisier by design.
- A transient loss of paru (landing on the `yay` rung) blocks AUR installs
  for that run.
- A compromised upstream tarball behind a bump-only diff isn't caught.
  That's accepted as outside what static review can see.
- `aur-vet audit`, a scan of installed foreign packages and npm/bun caches,
  runs on installer-created VMs only, never the operator's host. It is
  opt-in per VM profile through `verify.aur_audit` (forced with
  `--verify-aur`, like `--verify-boot`) and on in the desktop profile.

## Implementation notes
Choices made while building it, beyond the decision above:
- The engine is `scan.awk` + `bump-only.awk` beside the command. Data stays
  TAB-separated; a trailing backslash continues a record (one leading TAB
  dropped), so long EREs keep the 80-column limit. A scan error fails
  closed (exit 2), never "no findings".
- `PreBuildCommand = /usr/local/bin/aur-vet`, an absolute path, so nothing
  earlier on a user's PATH stands in for the vetter.
- No per-user `paru.conf` ships today (config lives in Programs' `home/`,
  ADR 0134). The Runner wires `/etc/paru.conf` after bootstrap and any
  per-user one Config Apply lays down; a bats guard covers every tracked
  `paru.conf`.
- Under `yay`, the Runner's AUR pass and `install-pkglist.sh`'s AUR list
  abort; User Programs get `AUR_HELPER="yay --repo"`, so their repo packages
  still install and an AUR-only one fails instead of building unvetted.
- A bump-only auto-accept carries the old commit's allowlist rows forward:
  by definition only version/checksum lines changed.
- The RPC has no ownership history, so orphan adoption is approximated:
  maintainer ≠ submitter and last modified < 14 days (unpinned packages).
- Commit dates are attacker-set, so the campaign window is checked against
  every commit's author/committer day plus the AUR's server-side
  LastModified; any in-window day is critical (backdating can't hide one).
- The PKGBUILD/.SRCINFO host cross-check expands plain top-level variables
  first; a host still unresolved is itself a mismatch.
- The paru/yay policy lives with the helper rule in `lib/aur-helper.sh`
  (`_aur_helper_vets_aur`, `_aur_helper_repo_cmd`).
- `verify.aur_audit` runs inside the plain first-boot sentinel only; with a
  pools/sessions/rollback verify the OK marker never appears, so the run
  fails loudly rather than silently skipping the audit.
- Hardening from the post-implementation review:
  - Bump-only lines must hold a bare value; code riding on a `pkgrel=` line
    is a real change. A NUL byte makes git print "Binary files differ",
    which is never a bump.
  - A binary is never silently skipped: NUL in a sourced file (PKGBUILD,
    `.install`, scripts) is critical, any other binary suspicious.
  - The installed copy ignores every `AUR_VET_*` override except
    `AUR_VET_UNATTENDED` (which only refuses prompts), so a user's
    environment can't redirect its store, data, RPC or sudo.
  - A pin with no recorded maintainer (accepted while the RPC was down) is
    suspicious until re-accepted, so the maintainer check can't lapse.
  - The system `paru.conf` is created if missing, so paru never runs
    unhooked.
- A maintainer change stays critical in the hook. The only way to accept
  a legit transfer is `sudo aur-vet repin <pkgbase>` (interactive): it
  shows the transition + diff and wants the new maintainer's name typed.
  AUR usernames are ASCII (`[A-Za-z0-9._-]`, aurweb `valid_username`); a
  name outside that falls back to the new commit's first 8 characters.
- No per-user paru.conf ships. `aur-vet doctor`, run at every login by
  `/etc/profile.d/aur-vet.sh`, warns when `$PARU_CONF`, the user's
  paru.conf or `/etc/paru.conf` lacks the hook.
