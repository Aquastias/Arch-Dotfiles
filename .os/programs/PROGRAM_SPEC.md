# Program authoring spec

Feed this file plus the relevant Arch Wiki page(s) to an LLM to generate a
compliant `config.jsonc` and `install.sh` for a new program.

---

## Invocation context

Every `install.sh` is sourced (not executed as a subprocess) by
`lib/run-program.sh` inside **arch-chroot**, running as the **owning user**
with temporary passwordless sudo. The shell stdlib is already sourced before
`install.sh` runs — do not re-source it.

Key consequences:

- No daemon is running inside the chroot. Use `systemctl enable`, never
  `systemctl start` or `systemctl restart`.
- `firewall-cmd` requires a running daemon — use `firewall-offline-cmd` instead.
- `virsh`, `zfs`, or any tool that talks to a live daemon must be deferred to a
  oneshot systemd service that runs on first boot.
- The chroot has network access. `paru` can reach the AUR.

---

## Shell stdlib — available helpers

These are provided by `lib/shell-stdlib.sh` and are available without sourcing:

```bash
print_status info    "message"   # → [program] message
print_status success "message"   # → [program] ✓ message
print_status warning "message"   # → [program] ⚠ message
print_status error   "message"   # → stderr; does NOT exit
command_exists "name"            # → true if name is on PATH
```

---

## `config.jsonc` format

```jsonc
// Program metadata for <name>.
//
// system=false → installed by the profile runner inside the chroot as the
// owning user via paru, with temp NOPASSWD sudo for <describe what sudo is
// needed for, e.g. "systemctl and /etc writes">.
// <One or two sentences explaining any non-obvious post-install state,
//  e.g. which groups are created, what the user must do post-boot.>

{
  "name": "<program-name>",     // must match the directory name exactly
  "system": false,              // always false — programs install as the user
  "description": "<one sentence: what is installed and what state it leaves>"
}
```

Rules:
- `"name"` must be the kebab-case directory name under `programs/<category>/`.
- `"system"` is always `false`. System-level packages go in `packages.jsonc`.
- `"description"` is one sentence, present tense, no trailing period.
- The header comment must name what sudo is needed for so readers understand
  why the script has elevated access.

---

## `install.sh` format

```bash
#!/usr/bin/env bash
# =============================================================================
# programs/<category>/<name>/install.sh
# =============================================================================
# Invoked by .os/lib/profiles.sh inside arch-chroot, as the owning user, with
# OS_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo granted.
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

```bash
paru -S --noconfirm --needed <pkg1> <pkg2>
```

- Always use `--needed` (idempotent).
- Prefer official repo packages; fall back to AUR only if the Arch Wiki says so.
- Split long package lists across lines with `\`.

### File writes

```bash
sudo tee /path/to/file >/dev/null <<'EOF'
...content...
EOF
```

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
- [ ] Header comment names every `sudo` operation performed
- [ ] All packages come from the Arch Wiki page for this program
- [ ] No `systemctl start` anywhere
- [ ] `systemctl enable` used for every service the Wiki says to enable
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
