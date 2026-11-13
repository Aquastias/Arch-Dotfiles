# fold-hung-tasks.awk — join a kernel hung-task report (its header line through
# `</TASK>`) into one journal line, so Known Noise can judge it whole by its
# stack (a virgl stall vs a real hang); every other line passes through. The
# collector ships this program into the guest (live.sh, _live_collect_script).

# A hung-task header: flush any open report, start a new one.
/ kernel: INFO: task .* blocked for more than / {
  if (on) print b
  b = $0; on = 1; next
}

# A kernel line inside a report: append it; `</TASK>` ends the report.
on && / kernel: / {
  l = $0; sub(/^.* kernel: +/, "", l); b = b " | " l
  if (l ~ /^<\/TASK>/) { print b; on = 0 }
  next
}

# Any other line ends an open report early.
on { print b; on = 0 }

# Every line not in a report passes through.
{ print }

# A report still open at the end.
END { if (on) print b }
