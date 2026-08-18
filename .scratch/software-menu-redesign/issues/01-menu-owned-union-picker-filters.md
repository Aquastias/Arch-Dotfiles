# 01 — Menu-Owned union + picker filters

**What to build:** Every registry Program governed by a dedicated menu control
stops appearing in a Programs picker. Introduce a single pure
`menu_owned_programs` aggregator that unions the existing
`printing_owned_programs` / `bluetooth_owned_programs` / `power_owned_programs`
with new owned-sets for the
Bootloader-owned `grub`, the Security-owned `firewalld` / `ufw` / `clamav` /
`rkhunter` / `apparmor`, the Backup-owned `borg` / `zfs-auto-snapshot`, and the
secrets-activated `sops`. Both Guided Installer program pickers subtract it, so
`_ctl_host_program_names` resolves empty (all six `kind: host` programs are
owned) and `_ctl_user_program_names` drops the Security/Backup-owned names while
keeping the five free-standing User Programs (`docker`, `podman`,
`virt-manager`, `searxng`, `teamspeak3`). Delisting only — no control default
changes, and the
stored slots are untouched (see ADR 0086, [[Menu-Owned Program]]).

**Blocked by:** None — can start immediately.

**Status:** done

- [x] A pure `menu_owned_programs` function emits the full owned union: the
      three existing service programs plus `grub`, `firewalld`, `ufw`, `clamav`,
      `rkhunter`, `apparmor`, `borg`, `zfs-auto-snapshot`, `sops`.
- [x] The new Security/Backup owned-sets enumerate exactly the names
      `post_install_programs` can derive (they must not drift from the
      derivation — cross-checked against `post-install.bats`).
- [x] `_ctl_host_program_names` resolves to the empty set; never lists `grub`.
- [x] `_ctl_user_program_names` excludes every Menu-Owned user program and still
      lists `docker`, `podman`, `virt-manager`, `searxng`, `teamspeak3`.
- [x] The existing service filtering (`cups`, `bluetooth`,
      `power-profiles-daemon`, `tuned`) still holds via the unified set.
- [x] Covered in `guided-controller.bats`, following the prior-art
      "picker omits the toggle-owned cups, keeps the rest" test.
