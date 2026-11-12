# lib/config/menu-rows.jq — the guided menu's rows (menu_rows), in one jq call
# for latency (ticket 04). Runs after menu-render.jq. Inputs (jq -n): $fields
# (the field table), $override / $baseline (the state maps), $lockpaths /
# $zfslock (the paths Manual Partitioning / a ZFS-less layout locks),
# $schema (the Install Defaults), $facts (filesystem, disk_kind, any_zfs).
# Output: [{section, field, label, value, overridden, locked}].

# The merged state, its facts, and the locale in each layer.
($baseline * $override) as $m
| $facts.filesystem as $fs
| $facts.disk_kind as $kind
| loc0($schema; "") as $sloc
| loc0($m; $sloc) as $mloc
| loc0($baseline; $sloc) as $bloc
| (($override | getpath(["system","locale"])) != null) as $loc_ov
| [ $fields[]
    | .path as $fp
    | ($fp | split(".")) as $pp
    # The field's default: the locale halves, the table's, or the schema's.
    | (if   $fp == "__language__" then loc_lang($sloc)
       elif $fp == "__encoding__" then loc_enc($sloc)
       elif .default != "" then .default
       else render($schema | getpath($pp); "") end) as $def
    # Impermanence is hidden for ext4/xfs (ADR 0040).
    | select($fp != "options.impermanence.enabled"
             or ($fs != "ext4" and $fs != "xfs"))
    | { section: .section,
        field:   $fp,
        label:   .label,
        value:
          (if   $fp == "__language__"
           then (loc_lang($mloc) | if . == "" then $def else . end)
           elif $fp == "__encoding__"
           then (loc_enc($mloc) | if . == "" then $def else . end)
           else render($m | getpath($pp); $def)
             | if . == "" then empty_label($fp) else . end end),
        # The ● flag: an override that changes the shown value.
        overridden:
          (if   $fp == "__language__"
           then ($loc_ov and (loc_lang($mloc) != loc_lang($bloc)))
           elif $fp == "__encoding__"
           then ($loc_ov and (loc_enc($mloc) != loc_enc($bloc)))
           else (($override | getpath($pp)) != null) end),
        locked:  (($kind == "manual"
                   and ($lockpaths | index($fp)) != null)
                  or (($facts.any_zfs | not)
                      and ($zfslock | index($fp)) != null)) } ]
