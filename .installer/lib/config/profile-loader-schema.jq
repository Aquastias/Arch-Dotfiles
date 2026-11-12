# lib/config/profile-loader-schema.jq — the closed-schema check (ADR 0036):
# the shortest path in $cfg that no schema pattern allows ("" when every key
# is allowed). Inputs (jq -rn): $cfg (the JSON), $pats (the patterns, one per
# line: "a.b", "a.*" for any key, "a[]" for any array index).

# parse_pat — a pattern line as tokens: "a[].*" → ["a", "[]", "*"].
def parse_pat:
  split(".")
  | map(if   . == "*"        then ["*"]
        elif endswith("[]")  then [.[0:length-2], "[]"]
        else [.] end)
  | add;

# tokmatch($p; $t) — does one path step match one pattern token?
def tokmatch($p; $t):
  if   $t == "[]" then ($p|type) == "number"
  elif $t == "*"  then ($p|type) == "string"
  else ($p|type) == "string" and $p == $t end;

# okprefix($P; $path) — does some pattern start with this path (a key, or a
# parent of allowed keys)?
def okprefix($P; $path):
  any($P[];
    . as $t
    | ($path|length) <= ($t|length)
    and all(range(0; $path|length); tokmatch($path[.]; $t[.])));

# render — a path as the user would write it: a.b[].c.
def render:
  . as $a
  | reduce range(0; ($a|length)) as $i ("";
      ($a[$i]) as $s
      | if   ($s|type) == "number" then . + "[]"
        elif $i == 0                then ($s|tostring)
        else . + "." + ($s|tostring) end);

# Every path of the config no pattern allows; the shortest one, rendered.
($pats | split("\n") | map(select(length > 0) | parse_pat)) as $P
| [ $cfg | paths ]
| map(select(okprefix($P; .) | not))
| sort_by(length)
| if length == 0 then "" else (.[0] | render) end
