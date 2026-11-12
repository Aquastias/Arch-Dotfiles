# lib/config/menu-render.jq — how the guided menu shows a value: jq
# definitions put before a program (menu_rows, menu_render_value), not a
# program on its own.

# empty_label($path) — what an empty value means, for the rows where blank
# would read as unset (display only: the stored value stays empty).
def empty_label($path):
  {"options.mirror_countries": "worldwide"}[$path] // "";

# render($v; $d) — one line for a value: an array comma-joined (an object
# element by its .name), an object as "key=value" pairs, a scalar as text;
# <d> when the result is null or empty.
def render($v; $d):
  (if   $v == null            then null
   elif ($v | type) == "array"  then
     ($v | map(if type == "string" then . else (.name // tostring) end)
         | join(", "))
   elif ($v | type) == "object" then
     ([$v | to_entries[] | "\(.key)=\(.value)"] | join(", "))
   else ($v | tostring) end) as $r
  | if ($r == null or $r == "") then $d else $r end;

# Locale projection (ADR 0076): the canonical system.locale (element 0 when an
# array) split into its language identity (.CODESET dropped, @modifier kept)
# and its encoding (the CODESET). loc0 falls back to <fallback> (the schema
# install default) so the two leaves render their defaults on a fresh state.
def loc0($src; $fallback): ($src.system.locale) as $l
  | (if ($l | type) == "array" then ($l[0] // "") else ($l // "") end)
  | if . == "" then $fallback else . end;
def loc_lang($l): ($l | sub("\\.[^.@]+"; ""));
def loc_enc($l):
  (if ($l | test("\\.[^.@]+")) then ($l | capture("\\.(?<e>[^.@]+)").e)
   else "" end);
