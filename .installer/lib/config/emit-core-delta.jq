# lib/config/emit-core-delta.jq — the effective config reduced to what it
# adds OVER Host Core (ADR 0056), so a saved profile stays layered. The
# inverse of the Layer Resolver's fold, key class by key class:
#   additive array  → subtract core's members
#   object          → drop keys whose value core already provides
#   everything else → drop when identical to core's value
# Inputs (jq -n): $eff (effective), $core (Host Core), $additive (the
# additive key patterns). Run after the Layer Resolver's prelude, which
# defines is_additive.

# prune($e; $c; $path) — what <e> adds over <c> at <path> (null: nothing).
def prune($e; $c; $path):
  if   ($c == null) then $e
  elif ($e == null) then null
  elif ($e | type) == "object" and ($c | type) == "object"
    then reduce ($e | keys_unsorted[]) as $k
      ({}; . as $acc
       | prune($e[$k]; $c[$k]; $path + [$k]) as $v
       | if $v == null then $acc else $acc + {($k): $v} end)
  elif ($e | type) == "array" and ($c | type) == "array"
    then if is_additive($path)
         # subtracting core leaving nothing means the layer adds nothing
         then ([$e[] | select(. as $x | $c | index($x) | not)]
               | if length == 0 then null else . end)
         # a replace key is dropped only when IDENTICAL to the core
         # value; an empty array is a deliberate choice (e.g. no
         # desktop) and must survive, not be read as "nothing to say".
         else (if $e == $c then null else $e end)
         end
  else (if $e == $c then null else $e end)
  end;

prune($eff; $core; [])
# an object that pruned empty carries no information — drop it
| walk(if type == "object"
       then with_entries(select((.value | type != "object")
                                or (.value | length > 0)))
       else . end)
