# check-regex.awk — exits 0 when ENVIRON["R"] is a valid awk regex. The report
# matches Known Noise with awk, so awk judges the regex: a bad one makes awk
# fail (exit 2). The regex comes through the environment, since -v would
# process its backslash escapes.

# Match the regex against an empty string, ignoring the result.
BEGIN { if ("" ~ ENVIRON["R"]) {} }
