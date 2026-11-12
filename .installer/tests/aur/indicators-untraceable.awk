# indicators-untraceable.awk — print every indicators.tsv row that cannot be
# traced (ADR 0143). Run with -F'\t' over, in order: sources.tsv,
# campaigns.tsv, indicators.tsv. A row is untraceable when its kind is
# unknown, its campaign is not in campaigns.tsv, its source is not in
# sources.tsv, or it does not have exactly 4 columns.
#
# In sources.tsv and indicators.tsv a trailing backslash continues a record
# on the next line (whose one leading TAB is dropped).

# sources.tsv: remember each source key (a continued key ends in `\`).
FILENAME ~ /sources/ {
  if (!/^#/ && !/^\t/ && NF) {
    key = $1
    sub(/\\$/, "", key)
    source_known[key]
  }
  next
}

# campaigns.tsv: remember each campaign id.
FILENAME ~ /campaigns/ {
  if (!/^#/ && NF) campaign_known[$1]
  next
}

# indicators.tsv: skip comments and blank lines.
/^#/ || !NF { next }

# A continued line: hold it until the record ends.
/\\$/ {
  held = substr($0, 1, length($0) - 1)
  next
}

# The record's last line: join it to the held part, then check the record.
{
  line = $0
  sub(/^\t/, "", line)
  record = held line
  held = ""
  count = split(record, column, "\t")
  if (column[1] !~ /^(pkgbase|npm|domain|sha256|path)$/ \
      || !(column[3] in campaign_known) || !(column[4] in source_known) \
      || count != 4)
    print record
}
