# Un-shadow the guided encrypted VM fixture

Status: done

## Parent

.scratch/guided-encryption-editor/PRD.md
ADR: docs/adr/0059-guided-encryption-editor.md

## What to build

Stop the VM Harness from bypassing the seam it is supposed to test.

The guided user-data renderer exports the `INSTALL_ENC_PASSPHRASE` preset for
every encrypted guided run. That preset is the **highest** precedence tier, so
it shadows the Secrets Manifest completely: no VM run has ever executed the
passphrase path the guided menu actually produces. This is exactly why the
five-character default shipped — the coverage that would have caught it ran
against a value the harness supplied, not the one the menu generates.

Remove the preset from the **guided** renderer only. The non-guided flows keep
theirs: they have no Secrets Manifest to read, so the preset is genuinely load
bearing there.

Only one fixture is both guided and encrypted, and it is install-only — it does
not verify boot — so no Console Answerer passphrase entry is involved and
nothing needs to type the new default at a boot prompt.

A preset that bypasses the code path under test is not coverage. After this
change the fixture drives Secrets Manifest → pool creation for real, so an
install that produces an unlockable pool fails the smoke run instead of passing
it.

## Acceptance criteria

- [x] The guided user-data renderer no longer exports the passphrase preset
- [x] Non-guided renderers still export their preset unchanged
- [x] The guided encrypted fixture resolves its passphrase from the Secrets
      Manifest, not from the preset
- [x] No fixture profile file needs editing (config fields untouched; only the
      header comment was refreshed to match)
- [x] Console Answerer behaviour is unchanged for boot-verifying fixtures
- [~] A VM smoke run of the guided encrypted fixture reaches installer exit 0
      — the live boot run stays HITL (ADR 0048); verified as far as the
      environment allows (see Comments), power-on deferred to the next smoke set

## Blocked by

- .scratch/guided-encryption-editor/issues/03-manifest-8char-default.md

## Comments

Closed at render level; the live boot run remains HITL by ADR 0048.

**Verified without booting** — the actual guest user-data the harness renders
for `single/guided-secure` (via `_seed_generator_render_guided_user_data`, not a
mock) was checked: no `INSTALL_ENC_PASSPHRASE` preset, replays `encryption=true`
+ `impermanence=true`, and the install line is `./install.sh --guided
/root/guided-answers` with no preset prefix — so the guided menu authors the
Secrets Manifest (`enc_passphrase` → `12345678`) and `collect_enc_passphrase`
reads it. The manifest → `zpool create` path this ticket exposes is now the one
that runs. `--print-config` also validates the fixture (encryption on). Bats:
`seed-generator-guided.bats` asserts the preset is gone; `zfs-pools.bats` covers
the precedence ladder.

**Why the power-on is deferred here** — four hard blockers in this environment,
any one fatal: (1) privilege escalation blocked, so `libvirtd` can't start; (2)
no `/dev/kvm`; (3) network egress restricted (ISO download + repo clone); (4)
the harness clones the published remote (`REPO_URL`), so it would install
committed `main`, not local unpushed work.

**To complete the live run** — on a KVM-capable, privileged, networked host,
once this branch is pushed: `OS_DIR=.os bash .os/vm/vm.sh --guided --profile
single/guided-secure` (optionally `REPO_URL=<fork>`), expecting
`===INSTALLER-EXIT-0===`.
