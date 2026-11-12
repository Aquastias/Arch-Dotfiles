# lib/config/post-install-programs.jq — the Program names a Security &
# Backup Extras selection installs, in canonical order (firewall first,
# backup last). Input: the post_install object. $zfs: "false" when the
# install has no ZFS (zfs-auto-snapshot is then left out).

# Coerce a non-object (absent, null, or a legacy bool) to off — `// {}`
# alone would keep a stored `true` and then index a boolean.
(if (.security | type) == "object" then .security else {} end) as $s
| (if (.backup | type) == "object" then .backup else {} end) as $b
# The firewall enum picks firewalld / ufw / neither; each toggle maps to
# its program.
| [ (if   $s.firewall == "firewalld" then "firewalld"
     elif $s.firewall == "ufw"       then "ufw"
     else empty end),
    (if $s.antivirus then "clamav"  else empty end),
    (if $s.rootkit   then "rkhunter" else empty end),
    (if $s.apparmor  then "apparmor" else empty end),
    (if $b.zfs_auto_snapshot and $zfs != "false"
     then "zfs-auto-snapshot" else empty end),
    (if $b.borg              then "borg" else empty end) ]
| .[]
