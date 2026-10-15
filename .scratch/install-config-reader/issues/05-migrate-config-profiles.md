# 05: Move config, profiles, Install State, picker, wipe, layout to the reader

**What to build:** config (non-reader modules), profiles, Install State,
picker, wipe and layout (~66 reads) read the Effective Config only through the
Install Config Reader — bound to JSON where the module holds JSON — with
no raw `// <default>` jq reads of config paths. Behaviour unchanged. Fields
missing from the schema get a row here. The raw-read lint baseline shrinks
by every migrated read. Decisions: candidate #1, Q17 (expand–contract batch).

**Blocked by:** 01, 02, 03

**Status:** done

- [x] No raw config reads left in this scope
- [x] Lint baseline entries for this scope removed
- [x] Scope's existing tests green; full suite green

## Comments

2026-10-15: environment.sh (display manager, wayland shell, stock) reads
the accessors; profile-loader's manual guard binds the Host Profile; wipe
target resolution asks the reader (`CONFIG_FILE="$1"`) for the disk kind.
menu.sh's `_MENU_ANY_ZFS_JQ` (a jq twin of install_config_any_zfs) deleted:
`menu_state_any_zfs` and the profile tree bind the reader; `menu_rows` gets
filesystem / disk kind / any-ZFS from `_menu_state_facts`. Reader's
lazy-source guard now checks its real dependency (`jsonc_read`); two
environment test setups gained the `jsonc_read` stub. config, guided, wipe
suites green; shellcheck + readability clean.

2026-10-15 (code review), unrecorded behaviour edges: in the menu's any-ZFS
(now the reader), a group with `filesystem: ""` inherits the root (old jq
kept `""`, i.e. not zfs). Empty strings are not valid filesystems; the reader
matches install. Group ashift defaults now come from the schema `ashift` row
(same value, 12); install_config_any_zfs = not manual + uses_filesystem zfs.
