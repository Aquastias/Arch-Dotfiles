# Feature Audit — findings surfaced while building the tool

Hidden errors met while implementing the audit (before the first full Audit
Run). Fixed in the fix session, with the run's `findings.md`.

- **grub + default `esp_size: auto` fails validation.** `esp_budget_auto_size`
  gives grub a fixed 512M ESP, then `layout_validate_esp_size` rejects it
  against the 1G floor (ADR 0038). Any grub install with the default ESP size
  aborts at validation. (`lib/boot/esp-budget.sh`, `lib/layout/core.sh`)
- **`options.bootloader` value is not validated.** A patch with
  `bootloader: "nope"` passes `validate_install_context`; the failure would
  surface only mid-install.
- **`desktop` host persist dirs are redundant.** `/home`, `/var/lib/docker`,
  `/var/lib/libvirt` each warn "already persistent. Redundant." at
  validation (`hosts/desktop/profile.jsonc`).
- **ADR 0117 autologin-by-default not provisioned.** The persistent flow
  never turns autologin on; a fresh persistent VM boots to the greeter until
  `vm-agent session <de>` writes the drop-in. ADR 0117 §2 says provisioning
  enables it by default (first compositor of the set).
- **`power.profile: tuned` aborts any install that includes KDE.** Plasma
  pulls `power-profiles-daemon`; the tuned program then installs `tuned-ppd`,
  which conflicts, and pacman aborts non-interactively ("unresolvable package
  conflicts", `programs/power/tuned/install.sh` line 18). Found by the first
  base run; the base now uses ppd and a `tuned` variant keeps the failure
  visible.
- **Noctalia plugin `eyecare` fetch fails at install** ("fetch failed
  (offline?) — skipped") with network up.
- **Static audit fails on two VM hosts.** `tests/audit.sh`: `arch-secure` →
  user `test` and `arch-data` → user `data` not found in `users/`.
- **VM Agent Control cannot reboot an encrypted persistent VM.** `vm-agent
  session|reboot` waits for the compositor, but the ZFS unlock prompt sits on
  serial (ADR 0099 routes the installed console there) with nothing answering
  it; the box hangs at the prompt until someone types the passphrase. The
  Feature Audit runs its own Console Answerer; a hand-driven debug VM does not.
