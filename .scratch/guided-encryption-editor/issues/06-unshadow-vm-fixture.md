# Un-shadow the guided encrypted VM fixture

Status: ready-for-agent

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

- [ ] The guided user-data renderer no longer exports the passphrase preset
- [ ] Non-guided renderers still export their preset unchanged
- [ ] The guided encrypted fixture resolves its passphrase from the Secrets
      Manifest, not from the preset
- [ ] No fixture profile file needs editing
- [ ] Console Answerer behaviour is unchanged for boot-verifying fixtures
- [ ] A VM smoke run of the guided encrypted fixture reaches installer exit 0
      (deferred — verified whenever the smoke set is next run by a human)

## Blocked by

- .scratch/guided-encryption-editor/issues/03-manifest-8char-default.md
