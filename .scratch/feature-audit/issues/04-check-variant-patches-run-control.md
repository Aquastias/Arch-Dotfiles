# 04: `check` + variant patches + run control

**What to build:** Audit Variants as JSON patches over the base.
`feature-audit check` (pure) resolves each base + patch to an Effective
Config and validates it like the VM Harness does. Adds variants: grub,
limine, refind, efistub, ufw, power-profiles-daemon, kde-pure, niri-pure,
hyprland-pure, minimal. `run` gains `--variant`, `--from`, `--keep`, runs
`check` first, destroys the VM between variants, and turns a fatal
install/boot failure into a Finding then continues.

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] Bad patch / invalid resolved config → `check` Finding, non-zero
- [ ] Each listed variant resolves; manifest cites ADRs per variant
- [ ] `--variant X` runs one; `--from X` resumes; `--keep` holds last VM
- [ ] Fatal abort recorded (phase + log path), run continues
- [ ] Bats for resolution/validation via fixture manifests
