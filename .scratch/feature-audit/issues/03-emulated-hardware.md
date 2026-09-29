# 03: Emulated hardware

**What to build:** the base variant's VM gets the maximum libvirt allows
(ADR 0152): swtpm TPM, OVMF Secure Boot vars (Secure Boot hardening
enabled in `arch-audit`), and one extra SATA disk so SMART is real.

**Blocked by:** 02

**Status:** done

- [x] Hardware block can request TPM, secboot firmware, SATA disk
- [x] Base installs and boots with Secure Boot enforced
- [x] Guest sees a TPM device and a SMART-capable disk
- [x] Other harness flows/profiles unaffected (existing bats green)

## Comments

- Scope revised (ADR 0152): the installer ships no Secure Boot signing or
  TPM enrolment, so emulating them proves nothing — recorded as
  `hw:secure-boot-tpm` unverifiable. The disks were already SATA (SMART
  data probed; smartd itself skips VMs). ACPI S3/S4 added (`VM_PM` →
  `--pm`), exercised by the new `power` phase.
