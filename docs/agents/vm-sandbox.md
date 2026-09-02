# VM harness under a sandbox

The VM Harness (`.installer/vm/vm.sh`) and every `virsh`/libvirt command it runs
talk to libvirtd over a Unix socket. When the harness runs inside a command
sandbox (e.g. Claude Code's Bash sandbox), that socket is often **blocked** — so
the command fails with a connection error even though libvirtd is running fine on
the host.

## The rule

**If a `virsh`/libvirt command is unreachable under the sandbox, retry the exact
same command with the sandbox disabled.** A script cannot disable its own
caller's sandbox — only the agent driving the shell can — so this is an agent
operating rule, not something `vm.sh` can do for you.

## The signal to watch for

`vm.sh` runs a reachability preflight and emits a recognizable message so you
know this is the sandbox case and not a genuinely dead daemon:

- **`libvirt unreachable (sandbox?)`** — libvirtd *is* running but `virsh` still
  cannot reach its socket. This is almost always a sandbox-blocked socket (or a
  permissions issue). **Retry the same command with the sandbox disabled.**
- **`libvirt unreachable`** (without the `(sandbox?)` qualifier) — libvirtd is
  not reachable at all. Start it (`sudo systemctl enable --now libvirtd`) first;
  if it is already up and you are sandboxed, retry outside the sandbox.

## What "retry outside the sandbox" means

Re-run the identical command with the sandbox turned off (in Claude Code, set
`dangerouslyDisableSandbox: true` for that Bash call). Treat each such command
individually — default back to the sandbox for the next unrelated command.

Do not add the libvirt socket or other sensitive paths to the sandbox allowlist
to work around this; disable the sandbox per-command instead.
