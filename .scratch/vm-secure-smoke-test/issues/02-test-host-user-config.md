Status: done

# Wire up Test Host arch-secure and Test User vm-test

## Parent

`.scratch/vm-secure-smoke-test/PRD.md` (ADR 0019)

## What to build

Create the Host Config, Install Template, and User Config for
the new Test Host `arch-secure` and Test User `vm-test`. These
are the non-secret config files that the merge + validation
machinery in `lib/profiles.sh` already consumes. No fixtures,
no VM script — purely config wiring.

Three files land in this slice:

1. `hosts/vm/arch-secure/config.jsonc` — Host Config that
   lists `vm-test` as the sole user and declares a minimal
   system-program set sufficient for the smoke test to do
   anything meaningful (at least the SOPS Runtime Service
   program; other system programs at the implementer's
   discretion based on what the existing
   `hosts/vm/arch-kde/config.jsonc` declares).
2. `hosts/vm/arch-secure/install.template.jsonc` — Install
   Template mirroring the config shape that the future
   `vm-secure.sh` will inline: `mode: "multi"`,
   `os_pool.topology: "mirror"`, `os_pool.disks:
   ["/dev/sda", "/dev/sdb"]`, `options.encryption: true`,
   `options.impermanence.enabled: true`,
   `options.age_key_url` pointing at the harness HTTP server
   (`http://192.168.122.1:9876/key.age`),
   `environment.desktop: []`, `post_install.{backup,
   security}: false`. Parity with
   `hosts/vm/arch-kde/install.template.jsonc`.
3. `users/vm-test/config.jsonc` — User Config declaring
   shell (`bash` or `zsh` — match the Host Core / arch-kde
   convention), sudo access, the standard `wheel` group, and
   a minimal user-program set. No `git` identity needed.

The new host name `arch-secure` is chosen specifically so the
libvirt domain name and the host-config directory cannot
collide with `arch-kde`, `arch-hyprland`, or
`arch-kde-hyprland` from existing scripts.

## Acceptance criteria

- [ ] `hosts/vm/arch-secure/config.jsonc` exists, parses as
      JSONC, and lists `vm-test` as a user.
- [ ] `hosts/vm/arch-secure/install.template.jsonc` exists,
      parses as JSONC, and contains `mode: "multi"`,
      `os_pool.topology: "mirror"`, two-disk `os_pool.disks`,
      `options.encryption: true`, `options.impermanence.
      enabled: true`, `options.age_key_url` pointing at
      `http://192.168.122.1:9876/key.age`,
      `environment.desktop: []`.
- [ ] `users/vm-test/config.jsonc` exists, parses as JSONC,
      and declares shell + groups + minimal user-program set.
- [ ] `tools/pick.sh` shows `arch-secure` in its host
      picker (smoke check — host has both `config.jsonc` and
      `install.template.jsonc`, so it must appear).
- [ ] The Host Core + Host Config merge for `arch-secure`
      produces a config whose program references all resolve
      (no User Config references a System Program — the
      validation rule from CONTEXT.md User Config).
- [ ] `shellcheck` passes on every changed shell file (if
      any) and `jq -e . < <(cpp -P ...)`-style JSONC parse
      checks pass on the three new files.
- [ ] Single commit, conventional-commit style, capitalized
      after the prefix.

## Blocked by

None - can start immediately. Independent of slice 01:
`secrets.json` is optional per CONTEXT.md User Secrets / Host
Secrets, so config validation runs cleanly even before the
fixtures land.
