# run-usage.awk — the usage text of run.sh: its header comment from line 2
# through the last mode (line 17), with the leading "# " removed.

# A header line: print it without its comment marker.
NR >= 2 && NR <= 17 { sub(/^# ?/, ""); print }
