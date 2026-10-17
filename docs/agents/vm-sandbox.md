# VM harness under a sandbox

The VM Harness (`.installer/vm/vm.sh`), `vm-agent.sh`, and the Combination
Matrix need three host resources a command sandbox (e.g. Claude Code's Bash
sandbox) can hide even though they exist on this box:

- **libvirt socket** — allowed (the seeded `sandbox.network.allowUnixSockets`).
- **`/dev/kvm`** — hidden (the sandbox mounts a minimal `/dev`): "no
  `/dev/kvm`", "no KVM".
- **Guest SSH** (192.168.122.x) — may be refused by the network filter: `ssh`
  timeouts.

**This dev box has KVM and libvirtd.** A "`/dev/kvm` absent" or
"libvirt unreachable" result from a sandboxed command is the sandbox, never a
reason to skip a VM run or report one as impossible.

## The rule

Run VM work (`vm.sh`, `vm-agent.sh`, `matrix.sh run`, `run.sh --vm`) with the
sandbox disabled — in Claude Code, `dangerouslyDisableSandbox: true` on that
Bash call. Default back to the sandbox for the next non-VM command.

## The signals

- **`libvirt unreachable (sandbox?)`** — libvirtd runs but `virsh` cannot reach
  its socket: retry the same command with the sandbox disabled.
- **`libvirt unreachable`** (no qualifier) — libvirtd is down. Start it
  (`sudo systemctl enable --now libvirtd`), then retry.
- **`matrix: preflight abort — no /dev/kvm`** while sandboxed — the hidden
  device: retry with the sandbox disabled.

A script cannot disable its caller's sandbox — only the agent driving the shell
can — so this is an agent operating rule, not something `vm.sh` does for you.
