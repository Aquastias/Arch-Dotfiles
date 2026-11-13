# lib/config/menu-render.jq — how the guided menu shows a value: jq
# definitions put before a program (menu_rows, menu_render_value), not a
# program on its own.

# empty_label($path) — what an empty value means, for the rows where blank
# would read as unset (display only: the stored value stays empty).
def empty_label($path):
  {"options.mirror_countries": "worldwide"}[$path] // "";

# render($value; $default) — one line for a value: an array comma-joined (an
# object element by its .name), an object as "key=value" pairs, a scalar as
# text; <default> when the result is null or empty.
def render($value; $default):
  (if   $value == null              then null
   elif ($value | type) == "array"  then
     ($value | map(if type == "string" then . else (.name // tostring) end)
         | join(", "))
   elif ($value | type) == "object" then
     ([$value | to_entries[] | "\(.key)=\(.value)"] | join(", "))
   else ($value | tostring) end) as $text
  | if ($text == null or $text == "") then $default else $text end;

# Locale projection (ADR 0076): the canonical system.locale (element 0 when an
# array) split into its language identity (.CODESET dropped, @modifier kept)
# and its encoding (the CODESET). locale_first falls back to <fallback> (the
# schema install default) so the two leaves render their defaults on a fresh
# state.
def locale_first($src; $fallback): ($src.system.locale) as $locale
  | (if ($locale | type) == "array" then ($locale[0] // "")
     else ($locale // "") end)
  | if . == "" then $fallback else . end;
def locale_language($locale): ($locale | sub("\\.[^.@]+"; ""));
def locale_encoding($locale):
  (if ($locale | test("\\.[^.@]+"))
   then ($locale | capture("\\.(?<encoding>[^.@]+)").encoding)
   else "" end);
