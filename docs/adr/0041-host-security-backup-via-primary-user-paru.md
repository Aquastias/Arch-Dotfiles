# Host security/backup tooling installed via the Primary User's paru pass

The Guided Installer's **Security** and **Backup** categories (and the host
`post_install.security` / `post_install.backup` objects they author) select
paru-based User Programs — `firewalld`/`ufw`/`clamav`/`rkhunter`/`apparmor` and
`zfs-auto-snapshot`/`borg`. Because these are `system:false` (paru refuses to
run as root) they cannot install via the System Program (chroot pacman) path;
instead the Runner unions the resolved program names into the **Primary User's**
(`users[0]`) paru pass — the same seam host AUR packages already use — so each
tool's existing Program Install Script runs unchanged.

## Considered Options

- **(a)** Flip the tools to System Programs (`system:true`), install host-wide
  via chroot pacman — rejected: their `install.sh` are written for `paru` +
  temp-NOPASSWD-sudo + owning-user context; paru refuses root, so this is a
  rewrite, not a flag flip.
- **(b)** Keep them per-user only, no host-level selection — rejected: the
  operator wanted a host-level, user-independent Security/Backup category with
  global defaults.
- **(c)** Host selection routed through the Primary User's paru pass — **chosen**.

## Consequences

- `post_install.security`/`post_install.backup` change shape from the old (dead)
  booleans to structured objects (`security`: one firewall + clamav + rkhunter +
  apparmor; `backup`: zfs-auto-snapshot + borg). The back-end default stays
  **absent = off**, so the Guided Installer's secure baseline is written
  **explicitly** on Save (a saved profile that omitted them would replay with no
  security).
- Security tooling is pruned from `users/aquastias/profile.jsonc` so the host
  Security category is authoritative (it can toggle a tool *off*); the Runner
  dedups a tool declared in both the host selection and a user's `programs`.
- A host with **no users** cannot carry security/backup tooling — a userless
  (server) install gets no firewall under this model. This is a pre-existing
  limitation of these being User Programs, now surfaced as a **fail-fast abort**
  at the terminal action rather than a silent skip.
- A ZFS-less install (ext4/xfs root with no ZFS pool or group, or Manual
  Partitioning) drops `zfs-auto-snapshot` at resolve time (2026-09-27): it
  would pull ZFS in from the AUR. The guided Backup screen mirrors this — the
  toggle is shown-but-locked as "off (no ZFS)" and edits are a no-op.

## Amendment (2026-10-02): AppArmor's kernel parameter is installer-owned

The apparmor program patched kernel parameters into grub and systemd-boot
only; ADR 0077 later added efistub, limine and refind, which it silently
skipped, so AppArmor stayed off on them (found by the first full Audit
Run). The `lsm=` parameter now comes from the installer: the Install State
carries whether AppArmor is selected, and every Bootloader Adapter appends
the fragment (`lib/boot/lsm.sh`, like zswap). The program only installs and
enables the service. Per the Arch Wiki, `lsm=` alone is set —
`apparmor=1 security=apparmor` were redundant (the kernel warned that
`security=` is superseded).

Rejected: teaching the program each loader's config (efistub keeps its
cmdline in NVRAM; every new loader would silently miss it again).
