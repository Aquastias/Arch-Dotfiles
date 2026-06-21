#!/usr/bin/env bash
# =============================================================================
# lib/config/post-install.sh — Security & Backup Extras resolver (ADR 0041)
# =============================================================================
# Pure core that turns a host's `post_install.{security,backup}` object into the
# things the back-end needs: the ordered list of Program names to install, the
# secure-baseline default object, and shape validation. No TTY, no disk writes,
# no paru — JSON in, decision out.
#
# The post_install object shape (ADR 0041):
#   security: { firewall: "firewalld"|"ufw"|"none", antivirus, rootkit,
#               apparmor }   (firewall enum; the rest bool)
#   backup:   { zfs_auto_snapshot, borg }   (bool)
# Every sub-field is optional; an absent field is OFF (matches the old
# `bool false` accessor default).
#
# Public API:
#   post_install_default               → the secure-baseline object (JSON)
#   post_install_programs   <json>     → ordered Program names, one per line
#   post_install_validate   <json>     → 0 when shape-valid, else error() + 1
# =============================================================================

# post_install_default — the secure baseline a fresh guided run pre-ticks:
# firewalld + clamav + rkhunter + apparmor and zfs-auto-snapshot + borg.
post_install_default() {
  jq -nc '{
    security: { firewall: "firewalld", antivirus: true, rootkit: true,
                apparmor: true },
    backup:   { zfs_auto_snapshot: true, borg: true }
  }'
}

# post_install_programs <post_install_json> — the ordered Program names the
# selection installs, one per line. The firewall enum picks firewalld / ufw /
# neither; the bool toggles map antivirus→clamav, rootkit→rkhunter, apparmor,
# zfs_auto_snapshot→zfs-auto-snapshot, borg. Canonical order (firewall first,
# backup last); an absent/false field contributes nothing.
post_install_programs() {
  jq -r '
    # Coerce a non-object (absent, null, or a legacy bool) to off — `// {}`
    # alone would keep a stored `true` and then index a boolean.
    (if (.security | type) == "object" then .security else {} end) as $s
    | (if (.backup | type) == "object" then .backup else {} end) as $b
    | [ (if   $s.firewall == "firewalld" then "firewalld"
         elif $s.firewall == "ufw"       then "ufw"
         else empty end),
        (if $s.antivirus then "clamav"  else empty end),
        (if $s.rootkit   then "rkhunter" else empty end),
        (if $s.apparmor  then "apparmor" else empty end),
        (if $b.zfs_auto_snapshot then "zfs-auto-snapshot" else empty end),
        (if $b.borg              then "borg" else empty end) ]
    | .[]
  ' <<<"${1:-{\}}"
}

# post_install_validate <post_install_json> — accept the object shape, reject
# the old bool form and malformed objects. Returns 0 when valid; otherwise
# calls error() with the offending path and returns 1. Rules: security/backup,
# when present, must be objects; security.firewall ∈ {firewalld,ufw,none};
# security.{antivirus,rootkit,apparmor} and backup.{zfs_auto_snapshot,borg},
# when present, must be bool. An absent field is valid (absent = off).
post_install_validate() {
  local bad
  bad="$(jq -rn --argjson pi "${1:-{\}}" '
    def boolfield($obj; $k):
      if ($obj | has($k)) and (($obj[$k] | type) != "boolean")
      then $k else empty end;
    [ if ($pi.security != null) and (($pi.security | type) != "object")
      then "security (must be an object, not the old bool form)" else empty end,
      if ($pi.backup != null) and (($pi.backup | type) != "object")
      then "backup (must be an object, not the old bool form)" else empty end,
      ( ($pi.security // {}) as $s
        | if ($s | has("firewall"))
             and ([$s.firewall] | inside(["firewalld","ufw","none"]) | not)
          then "security.firewall (must be firewalld | ufw | none)" else empty
          end ),
      ( ($pi.security // {}) as $s
        | boolfield($s; "antivirus"), boolfield($s; "rootkit"),
          boolfield($s; "apparmor") | "security." + . ),
      ( ($pi.backup // {}) as $b
        | boolfield($b; "zfs_auto_snapshot"), boolfield($b; "borg")
          | "backup." + . )
    ]
    | if length == 0 then "" else .[0] end
  ')" || { error "post_install_validate: jq failed"; return 1; }

  if [[ -n "$bad" ]]; then
    error "Invalid post_install field: ${bad} (ADR 0041)."
    return 1
  fi
}

# post_install_guard_users <post_install_json> <user_count> — the terminal-action
# guard (M5, ADR 0041). The Security & Backup Extras install via the Primary
# User's paru pass, so a non-empty selection on a userless host can never run.
# Returns 0 when the selection is empty OR there is at least one user; otherwise
# calls error() with an actionable message and returns 1.
post_install_guard_users() {
  local pi_json="${1:-{\}}" count="${2:-0}"
  local -a progs=()
  local _ex; _ex="$(post_install_programs "$pi_json")" || return 1
  [[ -n "$_ex" ]] && mapfile -t progs <<< "$_ex"
  if ((${#progs[@]} > 0)) && (("$count" == 0)); then
    error "Security/Backup Extras install via paru and need a primary user —" \
          "add a user or clear the selections."
    return 1
  fi
}
