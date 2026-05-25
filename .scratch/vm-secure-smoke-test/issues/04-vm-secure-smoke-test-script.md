Status: done

# Add vm-secure.sh end-to-end smoke test

## Parent

`.scratch/vm-secure-smoke-test/PRD.md` (ADR 0019)

## What to build

The final wiring script that ties together the fixtures from
slice 01, the Test Host / Test User from slice 02, and the
harness `VM_FIXTURE_FILES` hook from slice 03 into a single
one-command persistent VM that exercises SOPS + Impermanence +
ZFS native encryption on a 2-disk mirror.

`.os/vm/vm-secure.sh` follows the same shape as the existing
`vm-kde.sh` / `vm-hyprland.sh` / `vm-kde-hyprland.sh`:

- Declares `VM_NAME="arch-secure"`, `VM_DISK_SIZES=(40 40)`,
  `VM_RAM_MB=6144`, `VM_VCPUS=4` (or whatever matches
  existing defaults).
- Declares `VM_FIXTURE_FILES=("fixtures/key.age")` so the
  harness stages the Test Age Key into `${CACHE_DIR}`.
- Inlines an `INSTALL_CONFIG_CONTENT` heredoc with
  `hostname: "arch-secure"`, `mode: "multi"`,
  `os_pool.topology: "mirror"`,
  `os_pool.disks: ["/dev/sda", "/dev/sdb"]`, `ashift: 12`,
  `options.encryption: true`,
  `options.impermanence: { enabled: true, dataset:
  "rpool/persist", mount: "/persist" }`,
  `options.age_key_url:
  "http://192.168.122.1:9876/key.age"`,
  `options.bootloader: "systemd-boot"`,
  `options.kernel: "lts"`, `options.swap: true`,
  `options.esp_size: "512M"`,
  `environment.desktop: []`, `environment.gpu: "auto"`,
  `post_install.{backup,security}: false`,
  `storage_groups: []`.
- Sources `_harness.sh` and calls `run_harness "$@"`.

The script's header comment block documents:
- The combined feature set under test (SOPS + impermanence +
  encryption).
- The Test Age Key passphrase (`test`) that the operator
  types at the live-CD prompt when the Secrets Module asks.
- The manual verification checklist for post-install reboot:
  five Rollback Datasets exist on `rpool` with `@blank`,
  `/persist` mount is active, SSH host key survives reboot,
  SOPS Runtime Service decrypts on every boot, `ssh-to-age`
  output identical pre/post reboot, login as `vm-test` with
  the throwaway password works.
- A pointer to ADR 0019 and the PRD path.

No automated reboot-verification — matches existing `vm/*.sh`
behaviour (poweroff then restart-once, operator inspects
manually).

## Acceptance criteria

- [ ] `.os/vm/vm-secure.sh` exists, is executable, and
      follows the same structure as the existing
      `vm/vm-kde.sh`.
- [ ] The script declares `VM_NAME="arch-secure"`,
      `VM_DISK_SIZES=(40 40)`, and
      `VM_FIXTURE_FILES=("fixtures/key.age")`.
- [ ] The inlined `INSTALL_CONFIG_CONTENT` contains
      `mode: "multi"`, `os_pool.topology: "mirror"`, two-disk
      `os_pool.disks`, `options.encryption: true`,
      `options.impermanence.enabled: true`,
      `options.age_key_url:
      "http://192.168.122.1:9876/key.age"`, and
      `environment.desktop: []`.
- [ ] The script's header comment names the passphrase
      `test`, lists the manual verification checklist, and
      points at ADR 0019 + the PRD.
- [ ] `.os/vm/README.md` gains a row in the VM-flavors table
      for `vm-secure.sh` and a short note in the
      quick-start section, including the passphrase prompt.
- [ ] Running `bash .os/vm/vm-secure.sh --help` prints
      usage without error.
- [ ] Running `bash .os/vm/vm-secure.sh` on a host with
      libvirtd up creates the VM, boots the live ISO, types
      the installer command via `virsh send-key`, the
      operator types `test` at the Age-key passphrase
      prompt, install completes, VM powers off, harness
      restarts once into the installed system. (Manual smoke
      verification — not automated.)
- [ ] `shellcheck` passes on `vm-secure.sh`.
- [ ] Single commit, conventional-commit style, capitalized
      after the prefix.

## Blocked by

- `.scratch/vm-secure-smoke-test/issues/01-sops-fixture-infrastructure.md`
- `.scratch/vm-secure-smoke-test/issues/02-test-host-user-config.md`
- `.scratch/vm-secure-smoke-test/issues/03-harness-fixture-serving-hook.md`
