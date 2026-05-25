# PRD: Secure VM smoke test (sops + impermanence + encryption)

Status: ready-for-agent
Category: enhancement

## Problem Statement

The persistent VM scripts under `.os/vm/` (`vm-kde.sh`,
`vm-hyprland.sh`, `vm-kde-hyprland.sh`) all inline a config with
`encryption: false`, no `options.impermanence` block, and no
`options.age_key_url`. The Secrets Module, the Impermanence
install path (Persist Dataset, Rollback Hook, Blank Snapshot),
and ZFS native encryption are therefore unexercised by any
one-command persistent VM in the repo. The unattended side
(`.os/tests/vm/`) has scripts that cover some pairwise
combinations but none that covers all three together, and the
SOPS-touching ones require operator-supplied
`DOTFILES_REPO_URL` + `AGE_KEY_URL` because no committed test
fixtures exist anywhere. As a maintainer iterating on
secrets/impermanence/encryption code, there is no fast
one-command way to verify the combined install path still works.

## Solution

A new persistent VM script `.os/vm/vm-secure.sh` that exercises
SOPS + Impermanence + ZFS native encryption together on a
2-disk mirror, with all required fixtures committed to the
repo. The operator runs `bash vm/vm-secure.sh`, types the
hardcoded passphrase `test` at the live-CD prompt when the
Secrets Module asks, and ends up with an installed system whose
SOPS Runtime Service, Rollback Hook, and encrypted datasets are
all live.

Fixtures live as a normal Test Host (`hosts/vm/arch-secure/`)
and Test User (`users/vm-test/`) so no special-case code runs
in the installer. The Test Age Key is a passphrase-encrypted
`.age` file at `.os/vm/fixtures/key.age`; the existing harness
HTTP server serves it transparently, and `.sops.yaml` gains a
second `creation_rules` entry scoped to the two test paths so
the operator placeholder rule is untouched. The rationale is
captured in ADR 0019.

## User Stories

1. As a maintainer, I want a one-command persistent VM that
   installs with SOPS + impermanence + ZFS encryption all
   enabled, so that I can manually verify the combined path
   still works after changes to any of those subsystems.
2. As a maintainer, I want the VM script to share the existing
   `_harness.sh` flow, so that I don't have to learn a second
   harness shape.
3. As a maintainer, I want the script to default to a 2-disk
   mirror, so that the Layout Module's multi-disk path is
   exercised in the same run as the secrets and impermanence
   paths.
4. As a maintainer, I want the script to use a minimal server
   install (no desktop), so that signal stays on the features
   under test rather than display-manager or audio plumbing.
5. As a maintainer, I want all SOPS fixtures committed to the
   repo, so that the smoke test is self-contained and doesn't
   need an external dotfiles fork or an external Age key URL.
6. As a maintainer, I want the Test Age Key's passphrase to be
   the well-known string `test`, so that I never have to dig
   through docs to recall what to type at the live-CD prompt.
7. As a maintainer, I want the Test Host and Test User to live
   under the same paths as production hosts/users
   (`hosts/vm/arch-secure/`, `users/vm-test/`), so that no
   test-only code paths exist in the installer.
8. As a maintainer, I want the test fixtures to include both a
   user password and an `ssh_identity_private_key`, so that the
   SSH identity deployment path is exercised, not only the
   password path.
9. As a maintainer, I want the encrypted Age key to be served
   by the harness's existing HTTP server, so that no second
   server, no USB passthrough, and no external hosting is
   needed for the test to run.
10. As a maintainer, I want `.sops.yaml` to keep its operator
    placeholder rule untouched and gain a second rule scoped
    only to the test paths, so that adding the test fixtures
    never accidentally encrypts a real secret to the test
    recipient.
11. As a maintainer, I want a `regenerate.sh` next to the
    fixtures, so that rotating the Test Age Key (e.g. after
    changing the passphrase or after `age`'s KDF rotates) is a
    single command and doesn't drift from the original
    procedure.
12. As a maintainer, I want `regenerate.sh` to update
    `.sops.yaml`'s test-rule recipient and re-encrypt the
    committed `secrets.json` files via `sops updatekeys`, so
    that the four artifacts stay in lockstep without manual
    surgery.
13. As a maintainer, I want the harness to copy declared
    fixture files into its existing `${CACHE_DIR}` before
    starting the HTTP server, so that the same mechanism that
    serves the installer script also serves the Age key, with
    no second listener.
14. As a maintainer, I want the fixture-serving hook to be a
    declarative array (`VM_FIXTURE_FILES`), so that future
    fixture-driven VM scripts cost one array entry rather than
    a new harness branch.
15. As a maintainer, I want `hosts/vm/arch-secure/` to ship
    with an `install.template.jsonc` mirroring the inlined
    config, so that the host is selectable from `tools/pick.sh`
    on real hardware and the canonical per-host shape stays
    documented.
16. As a maintainer, I want the new VM script to mirror the
    poweroff-then-restart-once behaviour of the existing
    `vm/*.sh` scripts, so that the manual verification step
    matches the workflow I already have muscle memory for.
17. As a maintainer, I want the encrypted Age key file to live
    under `.os/vm/fixtures/`, so that the fixture data is
    co-located with the VM script that consumes it rather than
    scattered under the host directory.
18. As a maintainer, I want the cross-cutting impact (the
    `tests/vm/` sops/encrypted scripts retain their
    external-URL contract and don't get backported) called out
    explicitly, so that future readers don't assume the
    fixture pattern is universal.
19. As a maintainer, I want regenerate.sh to be tested, so
    that I have confidence the next fixture rotation produces
    a consistent set of artifacts.
20. As a maintainer, I want the harness fixture-serving hook
    to be tested, so that staging is verified independently of
    a live libvirt run.
21. As a maintainer, I want the test fixtures' throwaway
    nature documented, so that no future contributor mistakes
    the committed Age key for a production credential.
22. As a maintainer, I want the new host name (`arch-secure`)
    to differ from any existing host name in the repo, so that
    the libvirt domain and host-config directory never collide
    with `arch-kde` or future real hosts.

## Implementation Decisions

**VM script — `.os/vm/vm-secure.sh`**: Thin script in the same
shape as existing `.os/vm/vm-*.sh`. Declares
`VM_NAME="arch-secure"`, `VM_DISK_SIZES=(40 40)`,
`VM_RAM_MB=6144`, inlines an `INSTALL_CONFIG_CONTENT` heredoc,
sets `VM_FIXTURE_FILES` to point at `.os/vm/fixtures/key.age`,
sources `_harness.sh`, calls `run_harness "$@"`.

**Inlined config shape**: `mode: "multi"`,
`os_pool.topology: "mirror"`,
`os_pool.disks: ["/dev/sda", "/dev/sdb"]`,
`options.encryption: true`,
`options.impermanence.enabled: true` (with default `dataset:
"rpool/persist"`, `mount: "/persist"`),
`options.age_key_url: "http://192.168.122.1:9876/key.age"`,
`environment.desktop: []`, `post_install.{backup,security}: false`.

**Harness extension — `_harness.sh`**: A new declarative array
`VM_FIXTURE_FILES`. Before the HTTP server starts, each entry
is copied into `${CACHE_DIR}`. The function is the only
non-trivial addition to the harness and is exposed via a
documented contract: relative paths anchored to the script's
directory, files become available at
`http://${LIBVIRT_GATEWAY}:${HTTP_PORT}/<basename>`. Cleanup
happens via the existing `EXIT` trap because the entire
`${CACHE_DIR}` is already managed by the harness.

**Test Host — `hosts/vm/arch-secure/`**:
- `config.jsonc` lists `vm-test` as the sole user, declares a
  minimal system-program set (e.g. just the SOPS Runtime
  Service program).
- `install.template.jsonc` mirrors the inlined VM-script
  config (parity with `hosts/vm/arch-kde/`).
- `secrets.json` SOPS-encrypted under the Test Age Key,
  containing `root_password`.

**Test User — `users/vm-test/`**:
- `config.jsonc` declares shell, sudo access, groups, minimal
  user-program set, and (optionally) git identity.
- `secrets.json` SOPS-encrypted under the Test Age Key,
  containing `password`, `ssh_identity_private_key` (throwaway
  ed25519), and `ssh_identity_key_type: "ed25519"`.

**Fixture artifacts — `.os/vm/fixtures/`**:
- `key.age` — passphrase-encrypted Age key, passphrase `test`.
- `regenerate.sh` — deterministic regeneration script (see
  below).
- `README.md` — one short paragraph explaining the throwaway
  nature of the fixtures and pointing at ADR 0019 +
  `regenerate.sh`.

**Regeneration script — `.os/vm/fixtures/regenerate.sh`**:
Generates a fresh Age keypair via `age-keygen`, writes the
public key into `.sops.yaml`'s test-creation-rule recipient,
writes the private key passphrase-encrypted via `age` with
passphrase `test` to `key.age`, then runs `sops updatekeys`
against `hosts/vm/arch-secure/secrets.json` and
`users/vm-test/secrets.json` so the encrypted files re-key
to the new recipient without their plaintext changing. Idempotent.

**`.sops.yaml` update**: Add a second entry to
`creation_rules` whose `path_regex` matches *only*
`^hosts/vm/arch-secure/secrets\.json$` and
`^users/vm-test/secrets\.json$`, with `age:` set to the Test
Age Key's public half. The existing placeholder rule remains
the first match; the test rule comes after.

**Schema and contracts**: No changes to `install.jsonc` schema,
the Layout Module interface, the Secrets Module, or
`.os/lib/install-config.sh`. Everything new is data files plus
one harness array.

**Out-of-scope clarification (cross-cutting)**: The committed-
fixture pattern is *not* backported to
`.os/tests/vm/testing-single-disk-impermanent-kde-sops.sh` or
`testing-single-disk-impermanent-kde-encrypted.sh`. They keep
their operator-supplied `DOTFILES_REPO_URL` + `AGE_KEY_URL`
contract.

## Testing Decisions

Good tests in this codebase exercise external behaviour through
the public interface: drop inputs into the right place, run the
function, assert observable outputs. They do not poke at
internal globals or shape-of-implementation. Prior art:
`.os/tests/install-state.bats` (passes a fixture host directory,
asserts the produced JSON) and `.os/tests/audit.sh` (greps the
real tree, asserts structural invariants).

**Tests in scope**:

1. **`regenerate.sh`** — bats test. Run it from a clean
   working copy, then assert:
   - `key.age` exists and decrypts with passphrase `test` to a
     valid Age private key.
   - The decrypted private key's public half matches the
     `age:` value now in `.sops.yaml`'s test-creation rule.
   - The committed `hosts/vm/arch-secure/secrets.json` and
     `users/vm-test/secrets.json` both decrypt successfully
     using the regenerated key (i.e. `sops updatekeys` was
     applied).
   - Running `regenerate.sh` a second time produces a
     different keypair but leaves the secrets still
     decryptable.

2. **Harness fixture-serving hook** — bats test. Set
   `VM_FIXTURE_FILES` to a temp file with known contents, call
   the staging function in isolation (no HTTP server, no
   libvirt), and assert:
   - The file is present in `${CACHE_DIR}` with matching bytes.
   - Multiple entries are all copied.
   - An entry pointing at a missing file aborts with a clear
     error (not a silent skip).

**Tests out of scope**: An end-to-end `bash vm/vm-secure.sh`
run is not part of the automated suite — the VM script *is*
the smoke test, run manually.

## Out of Scope

- Backporting the committed-fixture pattern to
  `.os/tests/vm/testing-single-disk-impermanent-kde-sops.sh`
  or `testing-single-disk-impermanent-kde-encrypted.sh`.
- Covering other layout × feature combinations (single-disk
  encryption, raidz, desktop + impermanence). `.os/tests/vm/`
  remains the place to add those.
- Automating the reboot-verification checklist (`@blank`
  exists on each Rollback Dataset, `/persist` mounts, SOPS
  Runtime Service decrypts on every boot, ssh-to-age output
  identical pre/post reboot). The operator runs these
  manually.
- Replacing `age1REPLACE_WITH_OPERATOR_PUBLIC_KEY` in
  `.sops.yaml`'s first rule. That remains the operator's job;
  the new test rule is purely additive.
- Updating `CONTEXT.md` glossary — handled separately
  (proposed entries: *Test Age Key*, *VM Test Fixtures*, *Test
  Host*, *Test User*).

## Further Notes

- ADR 0019 (`docs/adr/0019-committed-sops-fixtures-for-vm-smoke-tests.md`)
  captures the trade-off between committed fixtures,
  on-the-fly generation, and operator-supplied URLs. The PRD
  does not re-litigate that decision.
- The harness's existing python HTTP server binds to
  `${LIBVIRT_GATEWAY}:${HTTP_PORT}`
  (`192.168.122.1:9876` by default). `lib/secrets.sh` uses
  `curl -fsSL`, which accepts plain HTTP, so no TLS is needed
  on the harness side.
- `age --decrypt` reads the passphrase from `/dev/tty` — the
  operator types `test` at the live-CD prompt during install.
  This is acceptable for a manual smoke test; full automation
  would require either pre-decrypting the key host-side and
  shipping plaintext (rejected: lib/secrets.sh always runs
  `age --decrypt`) or a piped-passphrase wrapper (rejected:
  out of scope for this PRD).
- The hostname `arch-secure` is chosen specifically so that it
  cannot collide with `arch-kde`/`arch-hyprland`/`arch-kde-hyprland`
  libvirt domain names from existing scripts.
