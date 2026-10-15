# 07: Move vm, tools and install.sh onto the reader

**What to build:** the VM Harness, tools and the bootstrap install entry
(~12 reads) read the Effective Config only through the Install Config
Reader — bound to JSON where the module holds JSON — with no raw `//
<default>` jq reads of config paths. Behaviour unchanged. Fields missing
from the schema get a row here. The raw-read lint baseline shrinks by every
migrated read. Decisions: candidate #1, Q17 (expand–contract batch).

**Blocked by:** 01, 03

**Status:** done

- [x] No raw config reads left in this scope
- [x] Lint baseline entries for this scope removed
- [x] Scope's existing tests green; full suite green

## Comments

2026-10-15: install.sh's CLI manual-layout guard asks the reader
(`CONFIG_FILE="$cli_positional" install_config_disk_kind`; the reader is
already loaded via lib/wipe/targets.sh). VM guided flow binds the seed for
encryption / impermanence (`install_config_get`); its "arch-guided" fallback
hostname is the flow's own name (hostname has no Install Default) —
`raw-config-ok`. vm.sh / tools had no schema-owned raw reads left after the
lint was scoped. Baseline now empty. vm + guardrail suites green.
