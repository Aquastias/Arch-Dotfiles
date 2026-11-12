# lib/profiles/runner-user-groups.jq — a user's supplementary groups as one
# comma-separated line, sorted and each once. Input: the user's profile
# JSON. A sudo user (`.sudo == true`) also gets `wheel`.

# The declared groups, plus wheel for a sudo user who did not list it.
(.groups // []) +
(if .sudo == true and ((.groups // []) | index("wheel") == null)
  then ["wheel"] else [] end)
| unique_by(.) | join(",")
