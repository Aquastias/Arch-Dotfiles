# equivalence-fields.jq — the config fields a Guided pick and `--profile` must
# agree on, normalised: the system block without the console font (the
# Guided baseline seeds it explicitly; its accessor already compares it), and
# every pool without its bound devices (those are picked at install time).
{
  system: (.system // {} | del(.console_font)),
  users, post_install, sysctl, persist, mode, ashift,
  os_pool: (.os_pool | del(.devices)?),
  storage_groups: ((.storage_groups // []) | map(del(.devices))),
  data_pools: ((.data_pools // []) | map(del(.devices)))
}
