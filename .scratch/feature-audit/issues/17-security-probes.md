# 17: Security probes

**What to build:** probes for apparmor (profiles enforced), clamav
(freshclam online, scan EICAR), firewalld/ufw (active, rules loaded),
rkhunter (check runs), sops (runtime secrets decrypted).

**Blocked by:** 09

**Status:** ready-for-agent

- [ ] One probe per program; firewall probe covers both variants
- [ ] Real run passes or yields Findings
