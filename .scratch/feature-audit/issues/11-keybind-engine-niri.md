# 11: Keybind engine + niri

**What to build:** VM Agent Control `key` (chord via `virsh send-key`)
and `mouse` (QEMU `input-send-event`). Binds-file contract: bind → expected
observable effect, `session_ending` flag, optional recovery. Parser
framework normalizing `(source, chord, action)`; niri parser + niri binds
file. Keybinds phase sends each bind as real input and asserts its effect;
session-ending binds run last with recovery. `check` flags parsed binds
with no expectation ("untested bind").

**Blocked by:** 08, 09

**Status:** ready-for-agent

- [ ] `key` / `mouse` verbs + pure-function bats
- [ ] niri parser bats against a fixture config
- [ ] Every shipped niri bind has an expectation; unmatched → Finding
- [ ] Failed effect → Finding with bind + expected effect
- [ ] Session-ending binds last; recovery restores the session
