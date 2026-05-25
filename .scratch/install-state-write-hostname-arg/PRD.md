Status: ready-for-agent

# PRD: install_state_write takes hostname as positional arg

References: ADR 0018.

## Problem Statement

`install_state_write` writes the install-state wire format JSON
that the host installer hands to the chroot. Its signature today
is `install_state_write <path>`, but the function reads two
globals that the signature does not name: `INSTALL_STATE_HOST_JSON`
(the merged Host Config, embedded in `.persist`) and
`RESOLVED_HOSTNAME` (used as `--arg hostname`).

The sole caller (in the chroot module) carries a two-line dance
every invocation: load the host config into the global, then call
the function. The signature hides both inputs; a future caller —
or a test author — has to read the body to discover them. The
`INSTALL_STATE_HOST_JSON` global is set in one place and read in
one place; it exists only to bridge two functions that should
share an argument instead.

`RESOLVED_HOSTNAME`, `LAYOUT_OS_POOL_NAME`, and
`LAYOUT_ESP_PARTS` are also globals the function reads, but the
last two are the Layout Module's published interface (ADR 0014,
ADR 0016) and intentionally global; `RESOLVED_HOSTNAME` is the
validated hostname consumed across many modules. The ad-hoc one
— the one worth fixing — is `INSTALL_STATE_HOST_JSON`.

## Solution

Change the signature to
`install_state_write <path> <hostname>`. The function loads the
Host Config internally via the existing
`load_host_config` helper and uses the passed-in hostname
throughout the body, including the `--arg hostname` line in the
`jq` invocation. The caller drops the global-staging line and
calls the function with two arguments. The
`INSTALL_STATE_HOST_JSON` global is removed from the codebase.

The Layout Module's published `LAYOUT_OS_POOL_NAME` and
`LAYOUT_ESP_PARTS` continue to be read as globals — they are the
seam's intended consumption pattern; converting them to args
would obscure the dependency on the Layout Module contract.

## User Stories

1. As an installer maintainer, I want
   `install_state_write`'s signature to name every input it
   needs, so that I do not have to read the body to discover
   required globals.
2. As an installer maintainer, I want the caller in the chroot
   module to be one line instead of two, so that the
   global-staging dance disappears.
3. As an installer maintainer, I want
   `INSTALL_STATE_HOST_JSON` to no longer exist in the
   codebase, so that there is one less ad-hoc cross-module
   global to reason about.
4. As an installer-test author, I want
   `install_state_write` to take its hostname directly, so
   that I can call it with a fixture hostname without
   pre-setting a global from another module's responsibility.
5. As an installer-test author, I want the test to exercise
   the real `load_host_config` path via a fixture host
   directory, so that the integration between
   install-state and Host Config is validated end-to-end.
6. As a future engineer reading the chroot module, I want the
   `install_state_write` call site to make obvious which
   hostname's state is being written, so that the variable
   passed (`$RESOLVED_HOSTNAME`) is visible at the call point.
7. As an operator running the install, I want the contents of
   `install-state.json` to be byte-identical to today's output,
   so that the chroot phase behaves exactly as before.
8. As a future engineer wondering why
   `LAYOUT_OS_POOL_NAME` and `LAYOUT_ESP_PARTS` are still
   read as globals while `INSTALL_STATE_HOST_JSON` was
   promoted to an argument, I want ADR 0018 to explain the
   distinction (published Layout Module interface vs. ad-hoc
   handshake), so that the asymmetry is principled.

## Implementation Decisions

- **New signature**: `install_state_write <path> <hostname>`.
  Both positional, both required.
- **Function body**: loads the merged Host Config internally
  via `load_host_config "$hostname"` (with the same
  `2>/dev/null || printf '{}'` fallback the caller used).
  Uses the passed-in `$hostname` for the `--arg hostname` line
  in the `jq` invocation (replacing the prior read of
  `$RESOLVED_HOSTNAME`).
- **Caller update**: the sole call site (in the chroot module)
  collapses to a single line, passing
  `"$RESOLVED_HOSTNAME"` as the second argument. The
  preceding `INSTALL_STATE_HOST_JSON=...` line and its
  `shellcheck disable=SC2034` comment are deleted.
- **Global removal**: `INSTALL_STATE_HOST_JSON` is removed
  from the codebase. No other reader exists.
- **Untouched global reads**: `LAYOUT_OS_POOL_NAME` and
  `LAYOUT_ESP_PARTS` continue to be read as published Layout
  Module interface (ADR 0014, ADR 0016). They are not
  converted to arguments.
- **Docstring updates**: the function header drops the
  "Required inputs (caller's scope)" block. The new signature
  is self-documenting.
- **Behaviour parity**: the rendered `install-state.json` is
  byte-identical to today's output for the same input
  (hostname + Host Config + Layout state).
- **Library boundary**: the function continues to live in
  the install-state module; no functional code moves between
  files.

## Testing Decisions

- **What makes a good test**: call `install_state_write` with
  a real path and hostname, point the test at a fixture host
  directory under `tests/fixtures/`, assert the rendered JSON
  matches expected shape and content. Do not stub
  `load_host_config` — exercising the real path validates the
  integration.
- **Modules to test**: the install-state module
  (`lib/install-state.sh`). Tests live in
  `tests/install-state.bats`.
- **Test shape**:
  - The existing test cases that exercised the
    `INSTALL_STATE_HOST_JSON` global are rewritten to pass
    the hostname positionally.
  - The fixture host directory contains a minimal merged
    Host Config (or relies on Host Core merging) that
    produces a known `.persist` sub-object.
  - Assertions cover: hostname interpolation in the JSON;
    persist sub-object content; behaviour when the host
    directory is absent (the `|| printf '{}'` fallback
    fires, persist sub-object is empty).
  - Existing assertions on the round-trip
    (`install_state_load` reads what
    `install_state_write` wrote) are preserved.
- **Prior art**: `tests/install-state.bats` already exercises
  the wire format with fixtures and tests the round-trip
  against `install_state_load`. The new tests adopt the same
  pattern but use the real `load_host_config` integration
  rather than pre-setting the global.
- **Coverage parity**: every assertion currently in
  `tests/install-state.bats` is preserved in the new
  structure.

## Out of Scope

- Converting `LAYOUT_OS_POOL_NAME` or `LAYOUT_ESP_PARTS` to
  positional arguments. Rejected — they are the Layout
  Module's published interface (ADR 0014, ADR 0016).
- Converting `RESOLVED_HOSTNAME` to an internal lookup
  (passing nothing, reading the global). Rejected — trades
  one hidden global for another.
- Linking the install-state schema
  (`_INSTALL_STATE_SCHEMA`) to the install-config schema
  introduced by ADR 0015. Cross-schema wiring is its own
  deepening.
- Changing the `install-state.json` shape, key order, or any
  field's value for the same input.
- Updating `CONTEXT.md` — install-state is implementation,
  not domain language.

## Further Notes

- **Single commit** — signature change + caller update +
  global removal + test rewrite land together. A split would
  leave either an unused arg or a missing global between
  commits.
- **Smallest of the deepening set** — narrowly-scoped to one
  function signature and its sole caller. No new module, no
  new abstraction.
- **Conventional shape** — the result is the
  obvious-in-hindsight pattern (function takes the inputs
  it needs). ADR 0018 exists primarily to explain the
  deliberate **asymmetry** with the Layout Module globals.
