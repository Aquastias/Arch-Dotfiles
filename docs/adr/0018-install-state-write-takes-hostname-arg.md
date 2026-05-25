# ADR 0018: install_state_write takes hostname as positional arg

## Status
Accepted

## Context
`install_state_write` (`lib/install-state.sh`) wrote the
host↔chroot wire format JSON but required the caller to pre-set
two globals first: `INSTALL_STATE_HOST_JSON` (the merged host
config it embeds in `.persist`) and `RESOLVED_HOSTNAME` (used as
`--arg hostname`). The function signature
(`install_state_write <path>`) hid both dependencies.

The sole caller (`lib/chroot.sh:251-254`) carried a two-line
dance every invocation:

```
INSTALL_STATE_HOST_JSON="$(load_host_config "$RESOLVED_HOSTNAME" \
  2>/dev/null || printf '{}')"
install_state_write "${MOUNT_ROOT}/root/lib-chroot/install-state.json"
```

`RESOLVED_HOSTNAME` and `LAYOUT_OS_POOL_NAME` / `LAYOUT_ESP_PARTS`
are also globals the function reads, but the latter two are
**published contracts** (Layout Module interface, ADR-0014/0016);
`RESOLVED_HOSTNAME` is the validated hostname consumed across many
modules. `INSTALL_STATE_HOST_JSON` was the only ad-hoc one — set
in one place, read in one place, undocumented in the signature.

## Decision
Change the signature to
`install_state_write <path> <hostname>`. The function calls
`load_host_config "$hostname"` internally and uses the passed
`$hostname` throughout the body (replacing both the
`INSTALL_STATE_HOST_JSON` read and the `--arg hostname
"$RESOLVED_HOSTNAME"` line). The caller collapses to one line:

```
install_state_write "${MOUNT_ROOT}/root/lib-chroot/install-state.json" \
                    "$RESOLVED_HOSTNAME"
```

`LAYOUT_OS_POOL_NAME` and `LAYOUT_ESP_PARTS` continue to be read
as globals — they are the Layout Module's published interface,
intentionally global, and converting them to args would add no
clarity (the function genuinely consumes the published layout
contract).

## Considered alternatives
- **Take `<host_json>` instead of `<hostname>`.** Rejected:
  forces every caller to do the `load_host_config` dance.
  Function becomes pure but the friction just moves to call sites.
- **Take no new arg; read `$RESOLVED_HOSTNAME` directly, load
  internally.** Rejected: trades one hidden global for another.
  The point is to make the input explicit.

## Consequences
- Caller boilerplate drops from 2 lines to 1; the
  `INSTALL_STATE_HOST_JSON` global is deleted from the codebase
  (was only ever set in chroot.sh, read in install-state.sh).
- Function is self-documenting: the signature names what it
  needs. No `shellcheck disable=SC2034` comment about
  cross-function global consumption.
- `tests/install-state.bats` adapts to pass the hostname
  positionally and uses a fixture host directory — exercises
  the real `load_host_config` path, slightly improving
  integration coverage.
- Two of the function's input globals remain
  (`LAYOUT_OS_POOL_NAME`, `LAYOUT_ESP_PARTS`). This is
  deliberate — they are published Layout Module interface,
  not hidden handshakes.
