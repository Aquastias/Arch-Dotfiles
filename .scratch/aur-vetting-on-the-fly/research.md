# Research: what makes a PKGBUILD suspicious (2026-09-28)

Input for moving [[AUR Vetting]] from Vetted Commits to install-time scanning
(ADR 0149). Web sources, read 2026-09-28; compared against
`.installer/aur/rules.tsv`.

## Real attacks

- **Atomic Arch (June 2026, ~1,500–1,935 packages).** Attackers adopted
  orphaned, popular packages and injected one line into the PKGBUILD or the
  `.install` scriptlet: `npm install atomic-lockfile …`, second wave
  `bun install js-digest` / `lockfile-js`. Upstream code untouched; npm added
  as a dependency; maintainer contact emails switched to Gmail. **Git commit
  metadata was spoofed** to look like trusted earlier committers (CSA note).
  Payload: infostealer + eBPF rootkit (`/sys/fs/bpf/hidden_*`), persistence
  in `/etc/systemd/system`, `/var/lib`, `~/.config/systemd/user`, exfil to a
  Tor C2 and `temp.sh`.
- **CHAOS RAT (July 2025).** New `-bin` packages (`librewolf-fix-bin`,
  `firefox-patch-bin`, `zen-browser-patched-bin`) whose PKGBUILD pulled from
  an unrelated GitHub repo.

## What scanners flag (ks-aur-scanner 117 rules, both `aurscan`s, aur-audit)

- **Download → shell** (covered): `curl …|sh`, `sh -c "$(curl …)"`
- **Named pkg-manager install** (covered): `npm i x`, `bun add`, `pip install
  x`
- **Decode/eval/blobs** (mostly): `base64 -d|sh`, `xxd -r`, hex, `rev`
- **Persistence** (covered): shell rc, cron, systemd units, autostart
- **Bad sources** (covered): paste, shortener, raw IP, `http://`, gist, `SKIP`
- **Indicators** (covered): campaign names, domains, hashes
- **Credential access** (missing): `~/.ssh`, GPG, keyrings, browser profiles,
  cloud/CI creds, env dump
- **Exfiltration** (partial): `curl -d @`/POST, `nc`, Discord/Telegram/Slack
  webhooks, DNS
- **Reverse shells** (`/dev/tcp` only): `nc -e`, `socat`, `mkfifo`, py/perl
  sockets
- **Privilege/tamper** (missing): `sudo` in `build()`, `chmod u+s`,
  sudoers/doas, PAM, `setcap`, `SigLevel` downgrade, `pacman-key --lsign`, CA
  trust injection, disabling AppArmor/firewall
- **Rootkit/kernel** (missing): `insmod`/`modprobe`, `/sys/fs/bpf`,
  `LD_PRELOAD`, `/etc/ld.so.preload`
- **Miners** (missing): `xmrig`, `stratum+tcp://`, wallet addresses
- **Metadata tricks** (missing): provides/replaces/conflicts a core or
  security pkg, `epoch`, `install=` outside repo, `backup=` of sensitive file,
  MD5/SHA1/missing checksums
- **Evasion** (missing): quote-splitting (`cu""rl`, `${IFS}`), `printf`
  assembly, `bash <<<`, `/tmp` exec, `nohup`/`setsid` detach
- **Repo oddities** (binary only): script behind `.png`/`.so`,
  `.envrc`/`.vscode/tasks.json`, hidden `.install`, missing referenced file
- **Gained risk** (pins only): latest commit adds a finding the previous
  lacked

## Consequences for the design

1. Git author/committer is attacker-set (Atomic Arch spoofed it), so a
   handover signal must come from the AUR RPC (`Maintainer`, `Submitter`,
   `LastModified`), which a push can't forge.
2. "Gained risk" survives without pins: scan `HEAD` and `HEAD~1` (already in
   the clone); a finding only `HEAD` has is escalated.
3. Add the missing categories above.
4. Normalise before matching (drop `""`/`''` splits and `${IFS…}`) so evasion
   doesn't dodge the regexes.
5. All sources agree static scanning misses novel/obfuscated attacks and
   opaque `-bin` payloads — the limit ADR 0143 already accepts.

## Sources

- https://github.com/lenucksi/aur-malware-check
- https://github.com/KiefStudioMA/ks-aur-scanner
- https://kief.studio/blog/security-scanner-for-aur-packages
- https://github.com/bfirestone/aurscan
- https://github.com/manticore-projects/aurscan
- https://github.com/nurazhardotcom/aur-audit (search listing; page 404)
- https://github.com/nightdevil00/AUR-Malware
- https://github.com/crizzler/AuraScan
- https://labs.cloudsecurityalliance.org/research/csa-research-note-aur-supply-chain-ebpf-rootkit-20260614-csa/
- https://www.sonatype.com/blog/atomic-arch-npm-campaign-adds-malicious-dependency
- https://www.stepsecurity.io/blog/400-aur-packages-hijacked-atomic-arch-campaign
- https://www.rescana.com/post/atomic-arch-supply-chain-attack-compromises-1-500-arch-user-repository-packages-credential-stealing-malware-targets-arch
- https://techheart.life/articles/atomic-arch-aur-malware-2026
- https://www.gamingonlinux.com/2026/06/the-arch-linux-aur-had-over-400-packages-compromised-with-malware/
- https://linuxsecurity.com/features/chaos-rat-in-aur
- https://www.webpronews.com/arch-linux-aur-malware-cryptominers-and-stealers-found-in-pkgbuilds/
- https://sebastianzehner.com/posts/aur-malware-attack-how-to-check-arch-linux-compromised/
