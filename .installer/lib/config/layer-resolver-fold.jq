# lib/config/layer-resolver-fold.jq — one profile layer over another (the
# Layer Resolver's fold, ADR 0057). Runs after the resolver's prelude
# (is_additive, odedup) and exclusions (apply_exclusions) definitions.
# Inputs (jq -n): $lower, $upper (the two layers), $additive (the additive
# key patterns). Output: the folded config.

# merge($a; $b; $path) — <b> over <a>: objects merge key by key, additive
# arrays concatenate (each value once), everything else is replaced by <b>.
def merge($a; $b; $path):
  if   ($a == null) then $b
  elif ($b == null) then $a
  elif ($a | type) == "object" and ($b | type) == "object"
    then reduce (($a + $b) | keys_unsorted | unique[]) as $k
      ({}; .[$k] = merge($a[$k]; $b[$k]; $path + [$k]))
  elif ($a | type) == "array" and ($b | type) == "array"
    then if is_additive($path) then (($a + $b) | odedup) else $b end
  else $b
  end;

# 1. inherit:false drops the lower layer base software wholesale — both
#    packages AND host_programs (the ADR 0089 base programs are the same
#    workstation base as the packages, so a bare install opts out of both
#    with the one flag). Compared to `false` directly: jq `//` treats
#    false as empty, so `(.inherit // true)` fails.
# `programs_inherit: false` is the user-fold twin of packages.inherit (ADR
# 0134): scoped to .programs only, so identity keys (groups/shell/sudo/
# ssh_authorized_keys) still fold. Harmless on the host fold — a host layer
# never carries programs_inherit.
((if ($upper.packages.inherit == false)
  then ($lower | del(.packages) | del(.host_programs))
  else $lower end)
 | (if ($upper.programs_inherit == false)
    then del(.programs) else . end)) as $base

# 2. fold, then strip the control keys so they never reach a consumer.
| merge($base; $upper; [])
| del(.packages.inherit)
| del(.programs_inherit)

# 3. exclusions over the merged result — UPPER layer only. A lower layer
#    excluding what it never inherited is vacuous, and applying it here
#    would block a later layer re-adding it, breaking "last layer wins".
#    apply_exclusions also strips control keys (re-read from the authored
#    layers next fold — how a later layer re-adds an excluded entry).
| apply_exclusions(
    ($upper.packages.exclude // []);
    ($upper.host_programs_exclude // []);
    ($upper.programs_exclude // []))
