# controller-profile-tree.jq — the options, environment, security and backup
# branches of the Profiles preview tree (ADR 0063), for a resolved profile.
#
# Arguments: $defaults the install defaults (options.kernel/bootloader/
# swap_size, environment.gpu), $any_zfs true when any pool is ZFS.

# onoff(v) — "on" for true, else "off".
def onoff(v): if v == true then "on" else "off" end;

# listed(v) — an array comma-joined, any other value as is.
def listed(v): v | if type == "array" then join(", ") else . end;

# desktops(v) — the desktop list, the first marked as the default session
# (ADR 0159) once there is a choice; "(none)" when empty.
def desktops(v):
  v | if type != "array" then .
      elif length == 0 then "(none)"
      elif length == 1 then .[0]
      else [.[0] + " (default)"] + .[1:] | join(", ") end;

# One tree line per setting, under its branch heading.
"  ▸ options",
"      └─ kernel: \(listed(.options.kernel // $defaults.options.kernel))",
"      └─ bootloader: \(.options.bootloader // $defaults.options.bootloader)",
"      └─ encryption: \(onoff(.options.encryption))",
"      └─ impermanence: \(onoff(.options.impermanence.enabled))",
"      └─ swap: \(if .options.swap == false then "off"
                  else .options.swap_size // $defaults.options.swap_size
                  end)",
"      └─ ssh: \(onoff(.options.ssh.enabled))",
"  ▸ environment",
"      └─ desktop: \(desktops(.environment.desktop // []))",
"      └─ gpu: \(listed(.environment.gpu // $defaults.environment.gpu))",
"  ▸ security",
"      └─ firewall: \(.post_install.security.firewall // "none")",
"      └─ antivirus: \(onoff(.post_install.security.antivirus))",
"      └─ rootkit: \(onoff(.post_install.security.rootkit))",
"      └─ apparmor: \(onoff(.post_install.security.apparmor))",
"  ▸ backup",
"      └─ snapshots: \(if $any_zfs
                       then onoff(.post_install.backup.zfs_auto_snapshot)
                       else "off (no ZFS)" end)",
"      └─ borg: \(onoff(.post_install.backup.borg))"
