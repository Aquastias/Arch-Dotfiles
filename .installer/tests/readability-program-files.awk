# readability-program-files.awk — the Readability Lint's checks on
# program files: `.jq` and `.awk` files (ADR 0167). Loaded first, before
# readability-scan.awk, so its rule sees these files before the shell
# scanner does; shell files pass through untouched.
#
# A program file starts with a header comment saying what it does.

FILENAME ~ /\.(jq|awk)$/ {
  if (FNR == 1 && $0 !~ /^#/)
    report("program-header", FILENAME, 1, "-",
           "no header comment on line 1")
  next
}
