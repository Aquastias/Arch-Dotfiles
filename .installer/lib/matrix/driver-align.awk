# driver-align.awk — align TAB-separated rows like `column -t`: every column
# padded to its widest entry plus two spaces (short rows padded too), the last
# column left unpadded, empty lines dropped.

# Keep each line; track the most columns and each column's widest entry.
{
  line[NR] = $0
  count = split($0, field, "\t")
  if (count > columns) columns = count
  for (i = 1; i <= count; i++)
    if (length(field[i]) > width[i]) width[i] = length(field[i])
}

# Print every non-empty line with its columns padded.
END {
  for (n = 1; n <= NR; n++) {
    if (line[n] == "") continue
    split(line[n], field, "\t")
    out = ""
    for (i = 1; i <= columns; i++)
      out = out (i < columns \
        ? sprintf("%-" (width[i] + 2) "s", field[i]) : field[i])
    print out
  }
}
