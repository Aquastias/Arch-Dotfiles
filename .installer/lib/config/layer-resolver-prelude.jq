# lib/config/layer-resolver-prelude.jq — jq definitions put before a
# program (odedup, is_additive), not a program on its own: the one
# classification predicate the fold and emit_core_delta share. Needs an
# $additive binding.
    def odedup: reduce .[] as $x ([];
      if any(.[]; . == $x) then . else . + [$x] end);

    # Is <path> (an array of key strings) an additive key? A trailing "*" in a
    # pattern matches exactly one further segment, so "packages.repo.*"
    # matches ["packages","repo","<any category>"].
    def is_additive($path):
      ($path | join(".")) as $flat
      | any($additive[];
          . as $pat
          | if ($pat | endswith(".*"))
            then ($pat | rtrimstr(".*")) as $stem
              | ($path | length) == (($stem | split(".")) | length) + 1
                and ($flat | startswith($stem + "."))
            else . == $flat
            end);
