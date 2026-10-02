# Program authoring spec

Feed this file plus the relevant Arch Wiki page(s) to an LLM to generate a
compliant `config.jsonc` and `install.sh` for a new program.

---

## Invocation context

Every `install.sh` is sourced (not executed as a subprocess) by
`lib/profiles/program-runner.sh` inside **arch-chroot**. The shell stdlib is already
sourced before `install.sh` runs — do not re-source it.

Two execution modes, selected by `"kind"` in `config.jsonc`:

- `kind: "user"` — runs as the **owning user** with temporary passwordless
  sudo. Packages installed via `paru` (AUR-capable). Use this by default.
- `kind: "host"` — runs as **root**. Packages installed via `pacman`. Use this
  only when the install genuinely needs root and no per-user state
  (e.g. deriving machine-wide keys, writing under `/etc`/`/usr/lib`
  unconditionally, bootloader setup). Listed under `host_programs` in the
  host config; runs before user programs.

Key consequences:

- No daemon is running inside the chroot. Use `systemctl enable`, never
  `systemctl start` or `systemctl restart`.
- `firewall-cmd` requires a running daemon — use `firewall-offline-cmd` instead.
- `virsh`, `zfs`, or any tool that talks to a live daemon must be deferred to a
  oneshot systemd service that runs on first boot.
- The chroot has network access. `paru` can reach the AUR.

---

## Shell stdlib — available helpers

Provided by `lib/shell-stdlib.sh` (facade over `lib/shell/*.sh`) and available
without sourcing:

```bash
print_status info    "message"   # → [program] message
print_status success "message"   # → [program] ✓ message
print_status warning "message"   # → [program] ⚠ message
print_status error   "message"   # → stderr; does NOT exit
command_exists "name"            # → true if name is on PATH
package_installed "pkg"          # → true if pkg installed (pacman -Qi)
check_root                       # → exits 1 if not running as root
send_user_notification "user" "title" "body"  # → notify-send as $user
```

Helpers live in `lib/shell/` (`output.sh`, `commands.sh`, `permissions.sh`,
`packages.sh`, `notifications.sh`), sourced via the `shell-stdlib.sh` facade.

---

## `config.jsonc` format

### `kind: "user"` (default)

```jsonc
// Program metadata for <name>.
//
// kind=user → installed by the profile runner inside the chroot as the
// owning user via paru, with temp NOPASSWD sudo for <describe what sudo is
// needed for, e.g. "systemctl and /etc writes">.
// <One or two sentences explaining any non-obvious post-install state,
//  e.g. which groups are created, what the user must do post-boot.>

{
  "name": "<program-name>",
  "kind": "user",
  "description": "<one sentence: what is installed and what state it leaves.>"
}
```

### `kind: "host"`

```jsonc
// Program metadata for <name>.
//
// kind=host → installed by the profile runner inside arch-chroot as root
// via pacman. <One or two sentences explaining what root-only work this
// script does — e.g. deriving machine keys, installing services under
// /usr/lib/systemd, patching bootloader.>

{
  "name": "<program-name>",
  "kind": "host",
  "description": "<one sentence: what is installed and what state it leaves.>"
}
```

### Optional fields

```jsonc
{
  ...
  "requires":  ["podman"],                          // ordered before this one
  "conflicts": ["ufw"],                             // cannot coexist
  "system_services": ["foo.service", "bar.timer"],  // enabled by runner
  "user_services":   ["baz.service"],               // enabled per-user
  "stow_opt_in":     true                           // stow only when named
}
```

- `requires[]` — other Programs whose install-time **setup** (package *and* its
  side effects — e.g. podman's subuid/subgid + linger) must already be in place
  when this one runs (ADR 0065). Validated at `validate_install_context` before
  any side effect: a required program must be a Host Program or listed earlier
  in the same user's `programs`. Declare only for cross-Program *setup ordering*
  — not for plain package deps, which pacman/paru already resolve.
- `conflicts[]` — other Programs this one is mutually exclusive with, e.g.
  firewalld vs ufw (ADR 0115). Symmetric: declaring on one side is enough.
  Validated at `validate_install_context` before any side effect — a selection
  with both aborts up front. Keep any runtime `command_exists` guard in
  `install.sh` as defense-in-depth for manual/partial runs.
- `system_services[]` — unit names the runner enables system-wide after
  `install.sh` finishes (via `systemctl enable` inside the chroot). Use this
  instead of calling `systemctl enable` from the script when the unit ships
  with the package.
- `user_services[]` — user units the runner symlinks into each owning user's
  `~/.config/systemd/user/default.target.wants/`.
- `stow_opt_in` — `./stow-configs.sh` with no names skips this program's
  `home/`; it stows only when named. For apps an operator host likely already
  configures by hand (vscodium, ADR 0148). Install-time Config Apply is
  unaffected.

Declare `requires`/`conflicts` the moment a genuine cross-Program relation
exists — before writing `install.sh` — so the fail-fast check, not a mid-install
abort, catches a bad selection.

Rules:
- `"name"` must be the kebab-case directory name under `programs/<category>/`.
- `"kind"` is required and must be `"user"` or `"host"`; use `"host"` only when
  root is required.
- `"description"` is one sentence, present tense, ends with a period.
- The header comment must name what sudo (or root) is needed for so readers
  understand why the script has elevated access.

---

## `install.sh` format

```bash
#!/usr/bin/env bash
# =============================================================================
# programs/<category>/<name>/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, <as the owning user with
# temp NOPASSWD sudo | as root>, with INSTALLER_DIR, PROGRAMS, SHELL_COMMONS
# pre-exported (plus AUR_HELPER on the user path — the resolved AUR Helper,
# paru or yay; install via ${AUR_HELPER} -S, never literal paru. Under yay it
# is `yay --repo`: AUR builds need paru for AUR Vetting, ADR 0143).
#
# <What the script does, in one to three sentences. Name every distinct action:
#  packages installed, files written, services enabled, groups created, etc.
#  Call out anything that is deferred to first boot.>
# =============================================================================

set -Eeuo pipefail
trap 'echo "[<name>] error on line $LINENO" >&2' ERR

# ... script body ...

print_status success "<Name> staged."
```

### Package installation

For `kind: "user"`:

```bash
${AUR_HELPER} -S --noconfirm --needed <pkg1> <pkg2>
```

For `kind: "host"`:

```bash
pacman -S --noconfirm --needed <pkg1> <pkg2>
```

- Always use `--needed` (idempotent).
- Prefer official repo packages; fall back to AUR only if the Arch Wiki says so
  (AUR access requires `kind: "user"` + `paru`).
- Split long package lists across lines with `\`.

### File writes

```bash
sudo tee /path/to/file >/dev/null <<'EOF'
...content...
EOF
```

(Drop `sudo` if running as root via `kind: "host"`.)

- Use `<<'EOF'` (single-quoted) to suppress variable expansion unless you need
  it, in which case use `<<EOF` and be deliberate.
- Set ownership and permissions explicitly after writing:
  ```bash
  sudo chown root:root /path/to/file
  sudo chmod 644 /path/to/file
  ```

### Editing existing files

```bash
sudo sed -i '/^#\?key *=/d' /path/to/file  # remove old (commented or not)
echo 'key = "value"' | sudo tee -a /path/to/file >/dev/null  # append new line
```

Prefer append-after-delete over in-place substitution when the line may or may
not already exist.

### Service management

Prefer declaring units in `config.jsonc` (`system_services` / `user_services`)
when the unit ships with the package. Otherwise enable in the script:

```bash
sudo systemctl enable <service>.service   # ✓ correct — deferred to boot
sudo systemctl start  <service>.service   # ✗ daemon not in chroot
```

For units that must run exactly once on first boot, install a oneshot service:

```bash
sudo tee /usr/lib/systemd/system/<name>-init.service >/dev/null <<'SVC'
[Unit]
Description=One-time init for <name>
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '<commands>'

[Install]
WantedBy=multi-user.target
SVC
sudo systemctl enable <name>-init.service
```

### Groups

```bash
getent group <group> >/dev/null || sudo groupadd <group>
```

Do not add users to groups here. User → group membership is declared per-user
in the user config (`groups: [...]`) and applied by the profile runner.

### Kernel parameters

If the program requires kernel parameters (e.g. AppArmor, IOMMU), patch both
bootloaders — the active one is not known at install time:

```bash
PARAMS_TO_ADD=("param1=value" "param2")

_inject_params_into_options_line() {
  local file="$1" current new param
  current=$(grep "^options " "$file" | sed 's/^options //')
  new="$current"
  for param in "${PARAMS_TO_ADD[@]}"; do
    [[ "$new" != *"$param"* ]] && new="$new $param"
  done
  if [[ "$new" != "$current" ]]; then
    sudo sed -i "s|^options .*|options $new|" "$file"
    return 0
  fi
  return 1
}

GRUB_DEFAULT_FILE="/etc/default/grub"
SBOOT_ENTRIES_DIR="/boot/efi/loader/entries"

if [[ -f "$GRUB_DEFAULT_FILE" ]]; then
  current=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" \
    "$GRUB_DEFAULT_FILE" | cut -d'"' -f2)
  new="$current"
  for param in "${PARAMS_TO_ADD[@]}"; do
    [[ "$new" != *"$param"* ]] && new="$new $param"
  done
  if [[ "$new" != "$current" ]]; then
    sudo sed -i \
      "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|"\
      "GRUB_CMDLINE_LINUX_DEFAULT=\"$new\"|" \
      "$GRUB_DEFAULT_FILE"
    command -v grub-mkconfig &>/dev/null && \
      sudo grub-mkconfig -o /boot/grub/grub.cfg
  fi
elif [[ -d "$SBOOT_ENTRIES_DIR" ]]; then
  while IFS= read -r -d '' entry; do
    grep -q "^options " "$entry" && \
      _inject_params_into_options_line "$entry" || true
  done < <(find "$SBOOT_ENTRIES_DIR" -name "*.conf" -print0)
else
  print_status warning "No bootloader config found;" \
    "skipping kernel param injection."
fi
```

### Conflict detection

If the program is mutually exclusive with another (e.g. firewalld vs ufw):

```bash
if command_exists "conflicting-tool"; then
  print_status error "<conflicting-tool> is installed;" \
    "<name> and it cannot coexist."
  exit 1
fi
```

### Post-boot instructions

If the user must take manual steps after first boot, say so in
`print_status success`:

```bash
print_status success "<Name> staged." \
  "Next steps: <what the user must do post-boot>."
```

---

## Checklist for the LLM

Before emitting output, verify:

- [ ] `config.jsonc` `"name"` matches the intended directory name
- [ ] `"kind"` value matches the header comment variant used
- [ ] `"description"` is one sentence, present tense, ends with a period
- [ ] Header comment names every `sudo`/root operation performed
- [ ] All packages come from the Arch Wiki page for this program
- [ ] `paru` used iff `kind: "user"`; `pacman` used iff `kind: "host"`
- [ ] No `systemctl start` anywhere
- [ ] Services that ship with packages declared in `system_services` /
      `user_services` instead of `systemctl enable` in the script
- [ ] `systemctl enable` (in-script) used only for units the script writes
- [ ] Every config value matches the Arch Wiki recommendation exactly
- [ ] Files written with `tee`, ownership/permissions set explicitly
- [ ] Groups created with `getent group ... || groupadd`, users not added
- [ ] Kernel params (if any) patch both GRUB and systemd-boot
- [ ] Script ends with `print_status success`
- [ ] `set -Eeuo pipefail` and `trap` are the first two non-comment lines
- [ ] `audit.sh` probe ships beside `install.sh` (Feature Audit, ADR 0152)

---

## Audit probe (`audit.sh`, `audit-binds.jsonc`) — Feature Audit

Every program ships an `audit.sh` (ADR 0152): the Feature Audit's proof the
program *works* on an installed system, not just that it installed.
`tools/feature-audit.sh check` fails on a program without one (unless the
Audit Manifest marks `program:<name>` unverifiable, with a reason).

- **Where it runs:** in the installed guest, sourced (not executed) by the
  audit's probe runner, once per account — root and every user of the
  variant — in two phases: guest internet **cut**, then restored. A check that
  fails offline but passes online is a "runtime fetch" Finding (the program
  was not fully set up at install).
- **Output:** one line per check, `PASS|FAIL|SKIP <check-id> <message>`.
  FAIL and any stderr are Findings; SKIP is not. Exit code is ignored.
  Check ids are `<program>-<what>`, stable across runs.
- **Helpers** (`lib/feature-audit/probe-lib.sh`, pre-sourced):
  `fa_pass/fa_fail/fa_skip`, `fa_check <id> <msg> <cmd…>`,
  `fa_require_pkg <probe> <pkg> || return 0` (SKIP when the package is
  absent), `fa_as_root`/`fa_as_user`, `fa_cfg <jq>`, `fa_unit_active`,
  `fa_no_stderr <cmd…>`, and the Probe Gate: `fa_gate <id> <reason> <cmd…>`
  (SKIP with a reason when the variant lacks what the check needs) with
  `fa_stock` / `fa_curated` / `fa_has_shell`. A program the variant does not
  select is skipped by the runner before its probe runs.
- **Env:** `FA_USER FA_HOME FA_IS_ROOT FA_ONLINE FA_PHASE FA_SESSION`
  (`niri|Hyprland|kwin_wayland|none`) `FA_DIR` (this probe's staged dir)
  `FA_CONFIG` (the variant's Effective Config); a user run also carries the
  live session's `WAYLAND_DISPLAY`/`DBUS_SESSION_BUS_ADDRESS`.
- **Depth:** prove behaviour — a service is active *and answers*, a plugin is
  loaded *and does its job*, a config parses with no startup warnings. Real
  hardware-only parts get `fa_skip` with the reason; the manifest's
  `unverifiable` list names them.
- **Timeout:** 600 s per account unless the probe declares
  `# audit-timeout: <sec>` in its header.
- **Fixtures:** optional `audit-fixtures/` next to `audit.sh`, staged as
  `$FA_DIR/audit-fixtures/`.
- **Keybinds:** a program that ships keybinds also ships
  `audit-binds.jsonc` — one expectation per shipped bind (format:
  `lib/feature-audit/binds.sh`; register the source there); a parsed bind
  with no expectation is a Finding.

Start from `programs/system/zsh/audit.sh`:

```bash
# shellcheck shell=bash
fa_require_pkg zsh zsh || return 0
fa_check zsh-startup "interactive zsh starts with no stderr" \
  fa_no_stderr zsh -i -c exit
```

---

## Prompt template

```
You are generating files for an Arch Linux installer.

Read the spec: <paste PROGRAM_SPEC.md here>

Read the Arch Wiki page: <paste wiki content here>

Generate:
1. config.jsonc for program "<name>" in category "<category>"
2. install.sh for the same program

Follow every rule in the spec. Use only packages and config values from the
Wiki page. Do not invent steps not mentioned on the Wiki.
```
