# lib/feature-audit/binds-plan.jq — match parsed bind rows to expectations
# (ADR 0152). Input: raw `source<TAB>chord<TAB>action` lines (jq -R); $e:
# the audit-binds.jsonc object. Shared by the host plan (binds.sh) and the
# guest (a program probe planning binds only its live dump sees).
def glob2re: gsub("(?<c>[.+?^$()\\[\\]{}|\\\\])"; "\\\(.c)")
             | gsub("\\*"; ".*") | "^" + . + "$";
select(length > 0) | split("\t") as [$s, $chord, $act]
| ($act | capture("^[^ ]+ +(?<a>.*)$").a // "" | gsub("^\"|\"$"; ""))
    as $arg
| ([$e.expect[] | select(.chord == $chord)
    # with an action too, the chord holds only for that action (mode)
    | select(. as $x | ($x.action | not)
             or ($act | test($x.action | glob2re)))]
   + [$e.expect[] | select(.action and (.chord | not))
      | select(. as $x | $act | test($x.action | glob2re))])[0] as $m
| { source: $s, chord: $chord, action: $act }
  + (if $m then ($m | del(.chord, .action))
       + { arg: (($m.arg // "") | gsub("\\{arg\\}"; $arg)
                 | gsub("\\{num\\}";
                        ($act | capture("(?<n>[0-9]+)").n // ""))) }
     else { effect: null } end)
