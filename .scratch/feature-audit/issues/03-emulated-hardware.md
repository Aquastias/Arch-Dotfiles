# 03: Emulated hardware

**What to build:** the base variant's VM gets the maximum libvirt allows
(ADR 0152): swtpm TPM, OVMF Secure Boot vars (Secure Boot hardening
enabled in `arch-audit`), and one extra SATA disk so SMART is real.

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] Hardware block can request TPM, secboot firmware, SATA disk
- [ ] Base installs and boots with Secure Boot enforced
- [ ] Guest sees a TPM device and a SMART-capable disk
- [ ] Other harness flows/profiles unaffected (existing bats green)
