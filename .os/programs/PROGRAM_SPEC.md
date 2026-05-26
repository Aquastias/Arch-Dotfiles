# Program authoring spec

Feed this file plus the relevant Arch Wiki page(s) to an LLM to generate a
compliant `config.jsonc` and `install.sh` for a new program.

---

## Invocation context

Every `install.sh` is sourced (not executed as a subprocess) by
`lib/run-program.sh` inside **arch-chroot**. The shell stdlib is already
sourced before `install.sh` runs — do not re-source it.

Two execution modes, selected by `"system"` in `config.jsonc`:

- `system: false` — runs as the **owning user** with temporary passwordless
  sudo. Packages installed via `paru` (AUR-capable). Use this by default.
- `system: true` — runs as **root**. Packages installed via `pacman`. Use this
  only when the install genuinely needs root and no per-user state
  (e.g. deriving machine-wide keys, writing under `/etc`/`/usr/lib`
  unconditionally, bootloader setup). Listed under `system_programs` in the
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

Domains under `lib/shell/` (`strings.sh`, `arrays.sh`, `directories.sh`,
`environments.sh`) are reserved for future helpers — currently empty.

---

## `config.jsonc` format

### `system: false` (default)

```jsonc
// Program metadata for <name>.
//
// system=false → installed by the profile runner inside the chroot as the
// owning user via paru, with temp NOPASSWD sudo for <describe what sudo is
// needed for, e.g. "systemctl and /etc writes">.
// <One or two sentences explaining any non-obvious post-install state,
//  e.g. which groups are created, what the user must do post-boot.>

{
  "name": "<program-name>",
  "system": false,
  "description": "<one sentence: what is installed and what state it leaves.>"
}
```

### `system: true`

```jsonc
// Program metadata for <name>.
//
// system=true → installed by the profile runner inside arch-chroot as root
// via pacman. <One or two sentences explaining what root-only work this
// script does — e.g. deriving machine keys, installing services under
// /usr/lib/systemd, patching bootloader.>

{
  "name": "<program-name>",
  "system": true,
  "description": "<one sentence: what is installed and what state it leaves.>"
}
```

### Optional fields

```jsonc
{
  ...
  "system_services": ["foo.service", "bar.timer"],  // enabled by runner
  "user_services":   ["baz.service"]                // enabled per-user
}
```

- `system_services[]` — unit names the runner enables system-wide after
  `install.sh` finishes (via `systemctl enable` inside the chroot). Use this
  instead of calling `systemctl enable` from the script when the unit ships
  with the package.
- `user_services[]` — user units the runner symlinks into each owning user's
  `~/.config/systemd/user/default.target.wants/`.

Rules:
- `"name"` must be the kebab-case directory name under `programs/<category>/`.
- `"system"` is `false` by default; set `true` only when root is required.
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
# Invoked by .os/lib/profiles.sh inside arch-chroot, <as the owning user with
# temp NOPASSWD sudo | as root>, with OS_DIR, PROGRAMS, SHELL_COMMONS
# pre-exported.
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

For `system: false`:

```bash
paru -S --noconfirm --needed <pkg1> <pkg2>
```

For `system: true`:

```bash
pacman -S --noconfirm --needed <pkg1> <pkg2>
```

- Always use `--needed` (idempotent).
- Prefer official repo packages; fall back to AUR only if the Arch Wiki says so
  (AUR access requires `system: false` + `paru`).
- Split long package lists across lines with `\`.

### File writes

```bash
sudo tee /path/to/file >/dev/null <<'EOF'
...content...
EOF
```

(Drop `sudo` if running as root via `system: true`.)

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
- [ ] `"system"` value matches the header comment variant used
- [ ] `"description"` is one sentence, present tense, ends with a period
- [ ] Header comment names every `sudo`/root operation performed
- [ ] All packages come from the Arch Wiki page for this program
- [ ] `paru` used iff `system: false`; `pacman` used iff `system: true`
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
