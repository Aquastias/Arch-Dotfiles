# byte-offset.awk — the 0-based byte offset of the text in the NEEDLE
# environment variable within the input file; nothing when it is absent.
# Used by: chroot-impermanence-helpers.bash (byte_offset). Run with LC_ALL=C
# so offsets count bytes, not characters.

# Read the whole file as one record.
BEGIN { RS = "^$" }

# Print where the needle starts, counting from 0.
{
  at = index($0, ENVIRON["NEEDLE"])
  if (at) print at - 1
}
