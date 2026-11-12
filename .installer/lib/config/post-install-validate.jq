# lib/config/post-install-validate.jq — the first malformed field of a
# post_install object ("" when it is valid). Input (jq -n): $pi, the object.

# boolfield($obj; $k) — <k> when <obj> has it as something other than a bool.
def boolfield($obj; $k):
  if ($obj | has($k)) and (($obj[$k] | type) != "boolean")
  then $k else empty end;

# security and backup must be objects (not the old bool form); firewall is
# an enum; every toggle is a bool.
[ if ($pi.security != null) and (($pi.security | type) != "object")
  then "security (must be an object, not the old bool form)" else empty end,
  if ($pi.backup != null) and (($pi.backup | type) != "object")
  then "backup (must be an object, not the old bool form)" else empty end,
  ( ($pi.security // {}) as $s
    | if ($s | has("firewall"))
         and ((["firewalld","ufw","none"] | index($s.firewall)) == null)
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
