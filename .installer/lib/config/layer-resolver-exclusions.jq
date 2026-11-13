# lib/config/layer-resolver-exclusions.jq — jq definitions put before a
# program (apply_exclusions), not a program on its own: subtract-then-strip,
# shared by the fold and the guided path.
    def _drop($excl): map(select(. as $p | $excl | index($p) | not));
    def _drop_cats($excl): with_entries(.value |=
      (if type == "array" then _drop($excl) else . end));

    # apply_exclusions($pkg; $sys; $usr) — subtract each from its slot, then
    # strip the exclude control keys and prune an emptied packages object.
    def apply_exclusions($pkg_excl; $sys_excl; $usr_excl):
      (if (.packages.repo // null) != null
       then .packages.repo |= _drop_cats($pkg_excl) else . end)
      | (if (.packages.aur // null) != null
         then .packages.aur |= _drop_cats($pkg_excl) else . end)
      | (if (.host_programs // null) != null
         then .host_programs |= _drop($sys_excl) else . end)
      | (if (.programs // null) != null
         then .programs |= _drop($usr_excl) else . end)
      | del(.packages.exclude)
      | del(.host_programs_exclude)
      | del(.programs_exclude)
      | if (.packages // null) == {} then del(.packages) else . end;
