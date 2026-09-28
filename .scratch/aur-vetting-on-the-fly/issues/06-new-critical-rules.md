# 06: New critical rules

**What to build:** The research's missing high-risk categories become rules
(data rows): credential access (`~/.ssh`, GPG, keyrings, browser profiles,
cloud/CI credential files, env dumps), exfiltration (HTTP POST/upload of
files, `nc` transfer, Discord/Telegram/Slack webhooks, DNS exfil), reverse
shells (`nc -e`, `socat`, `mkfifo`, interpreter socket shells), rootkit /
kernel (`insmod`/`modprobe`, `/sys/fs/bpf`, `LD_PRELOAD`,
`/etc/ld.so.preload`) and miners (`xmrig`, `stratum+tcp://`, wallet
addresses). Research: `.scratch/aur-vetting-on-the-fly/research.md`.

**Blocked by:** 05 (Obfuscation stripping).

**Status:** ready-for-agent

- [ ] ≥1 positive and ≥1 negative rule-case row per new rule
- [ ] Benign fixtures (electron `npm ci`, rust, benign-dep) still pass
- [ ] Rule rows keep the 80-column continuation convention
