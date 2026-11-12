# lib/config/locale-parts.awk — locale, keymap and console-font names: one
# name per input line (only the first field is read). -v part= picks what to
# print for each line:
#   language  en_US.UTF-8 → en_US, sr_RS.UTF-8@latin → sr_RS@latin
#             (the .CODESET dropped, any @modifier kept)
#   encoding  en_US.UTF-8 → UTF-8 (nothing when there is no codeset)
#   charsets  with -v wanted=<language>: the second field ("<locale>
#             <charset>" in /usr/share/i18n/SUPPORTED) of each line of that
#             language
#   keymap    de-latin1.map.gz → de-latin1 (a kbd keymap file)
#   font      lat2-16.psfu.gz → lat2-16 (a console font file, before its .)
# Used by: lib/config/locale-parts.sh, lib/config/locale-source.sh.

# language(name) — the name without its first .CODESET (the text from a .
# up to the next . or @).
function language(name) {
  sub(/\.[^.@]*/, "", name)
  return name
}

part == "language" { print language($1) }

# The codeset: the text after the first . up to the next . or @.
part == "encoding" && match($1, /\.[^.@]*/) {
  print substr($1, RSTART + 1, RLENGTH - 1)
}

part == "charsets" && language($1) == wanted && $2 != "" { print $2 }

part == "keymap" { name = $1; sub(/\.map\.gz$/, "", name); print name }

part == "font" { name = $1; sub(/\..*/, "", name); print name }
