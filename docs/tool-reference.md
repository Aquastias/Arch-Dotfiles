# Tool Reference

Every command the repo's shell code may call, and every flag it may pass,
each with what it means and an example from the repo ([ADR 0167]). If a
line of code puzzles you, look its command up here.

This doc is also the allowlist. The Readability Lint fails on a command or
flag that is not listed here (strict in Migrated Areas, advisory
elsewhere). To use a new command or flag, add its entry first.

## How an entry is written

```markdown
### `cut`
Prints selected fields of each line.

- `-d <delimiter>` — the character between fields
- `-f <fields>` — which fields to print (`1`, `2,3`, `2-`)

Example: `cut -d: -f1 /etc/passwd` — every user name.
```

- The heading holds the command name, alone, in backticks.
- A flag bullet starts with the flag in backticks. A `<placeholder>` after
  the flag means it takes a value (`-d :` or `-d:`).
- Two spellings of one flag share a bullet: `` `-r`, `--raw-output` ``.
- Short flags may be joined in code (`rm -rf` = `rm -r -f`); list each
  letter on its own.
- Functions defined in the repo need no entry.

Order of preference ([ADR 0167]): builtins and coreutils first, then jq,
grep and sed in their small forms, awk only as `.awk` files, and Domain
Tools where nothing else does the job.

## Bash Feature Tier

The bash syntax code may use ([ADR 0167]). The lint flags the banned
forms (`bash-feature`).

Allowed:

- `[[ … ]]` — a test: `[[ -f "$file" && "$mode" == fast ]]`
- `$( … )` — a command's output as text: `today="$(date -u +%F)"`
- arrays — `names=(a b)`, `names+=(c)`, `"${names[@]}"` (every item),
  `"${names[*]}"` (every item joined by spaces into one word),
  `"${names[-1]}"` (the last),
  `"${names[0]}"` (the first)
- `${#names[@]}` — how many items an array holds; `${#text}` — how many
  characters a variable holds
- `${!names[@]}` — an array's keys (associative arrays)
- `mapfile -t lines < <(…)` — a command's output lines into an array
- `while IFS= read -r line; do … done < <(…)` — loop over output lines
  (`< <(…)` feeds the loop without a subshell, so variables set inside
  survive)
- `${var:-default}` — the value, or `default` when unset or empty
- heredocs — `cat <<'EOF'` … `EOF` (quoted `'EOF'`: nothing expands)
- `local` — function-local variables
- `(( … ))` — plain arithmetic: `(( count += 1 ))`, `(( count > 3 ))`

Banned, and what to write instead:

- `${!name}` (read the variable whose name is in `name`) — pass the value
  itself, or use an associative array
- `declare -n` / `local -n` (namerefs) — return values by printing them
- `eval` — call the function or command directly
- `<<<` (here-string) — `printf '%s\n' "$text" | command`
- `BASH_REMATCH` (regex captures) — `cut`, `grep -o`, or an `.awk` file
- pattern operators: `${var#x}`, `${var##x}`, `${var%x}`, `${var%%x}`,
  `${var/a/b}`, `${var//a/b}`, `${var^^}`, `${var,,}`, `${var@Q}` —
  `basename`, `dirname`, `cut`, `tr` or `sed -i`
- `printf -v name` — `name="$(printf …)"`

The one exception is the bootstrap line that finds a script's own
directory before anything else is sourced:

```bash
script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"
```

## jq features

Allowed inside a jq program ([ADR 0167]):

- paths — `.users[0].name`, `.options.kernel`, `.[]` (every item)
- `//` — a fallback: `.esp_size // "1G"`
- `select(…)` — keep items where the test is true:
  `.users[] | select(.admin)`
- `map(…)` — change every item of an array: `map(.name)`
- `keys` — an object's keys, sorted
- `length` — how many items (or characters)
- `has("key")` — whether an object has the key
- `|` — feed one step's result into the next
- comparisons and `and` / `or` / `not`, `if … then … else … end`
- object and array building: `{name: .name}`, `[.[] | .id]`, and joining
  with `+`: `$array + [$item]`, `$a + {disks: $d}`
- updating a field: `.mode = "multi"` (set it), `.os_pool |= (. // {})`
  (replace it with a function of itself), `.group += {disks: $d}` (add to
  it)
- `.[$key]` — the field whose name is in `$key`; `.list[]?` — every item,
  or nothing when `.list` is not a list
- `type` — the value's kind (`"object"`, `"array"`, `"string"`, …);
  `empty` — no result at all; `del(.a)` — the value without `.a`;
  `index($v)` — where `$v` sits in an array (`null` when absent)
- `$name` — a value passed with `--arg` / `--argjson`

Banned, the lint flags them (`jq-feature`): `reduce`, `foreach`, `walk`,
`def`, `paths`, `getpath`, `setpath`, `inputs`. Write a bash loop over
simple jq output instead; when bash truly cannot express it, move the
program to a commented `.jq` file read with `jq -f`.

## Builtins

Commands built into bash. `help <name>` shows bash's own text for each.

### `[`
Tests a condition; same as `test`. Exit status 0 means true. Close it
with `]`. Prefer `[[ ]]` in new code; `[` stays in bats assertions.

- `-e <path>` — the path exists
- `-f <path>` — the path is a regular file
- `-d <path>` — the path is a directory
- `-L <path>` — the path is a symlink
- `-s <path>` — the file exists and is not empty
- `-x <path>` — the file is executable
- `-z <text>` — the text is empty
- `-n <text>` — the text is not empty
- `-eq`, `-ne`, `-lt`, `-gt`, `-le`, `-ge` — numbers: equal, not equal,
  less than, greater than, less or equal, greater or equal

Example: `[ "$status" -eq 0 ]` — the last `run` succeeded.

### `test`
Same as `[`, without the closing `]`.

- `-f <path>` — the path is a regular file
- `-s <path>` — the file exists and is not empty

Example: `test -s "$HOME/.config/qt6ct/qt6ct.conf"`

### `:`
Does nothing and succeeds. Used as an empty function body.

Example: `history_load() { :; }`

### `.`
Same as `source`.

### `source`
Runs a file in the current shell, so its functions and variables stay
defined afterwards.

Example: `source "$INSTALLER_DIR/lib/common.sh"`

### `local`
Declares variables visible only inside the current function.

- `-a` — the variable is an indexed array
- `-A` — the variable is an associative array (string keys)
- `-l` — keep the value in lower case (`local -l word="KDE"` → kde)
- `-u` — keep the value in upper case (`local -u first="k"` → K)

Example: `local -a kept=()`

### `declare`
Declares variables, or lists functions.

- `-a` — an indexed array
- `-A` — an associative array (string keys)
- `-g` — global, even when declared inside a function
- `-F` — print function names only; with a name, succeeds when the
  function exists
- `-f` — print a function's full definition
- `-p` — print a variable's declaration

Example: `declare -F install_config_use_json >/dev/null` — is the
function defined?

### `readonly`
Declares a variable that can never change.

- `-a` — an indexed array

Example: `readonly _RUNNER_SUDO_DROPIN="/etc/sudoers.d/01-profiles-runner"`

### `export`
Makes a variable (or function) visible to child processes.

- `-f` — export a function, so a child `bash` can call it

Example: `export INSTALLER_DIR="$TEST_DIR"`

### `unset`
Removes a variable or function.

- `-f` — remove a function

Example: `unset -f zfs logger` — drop test stubs.

### `echo`
Prints its arguments and a newline. Prefer `printf` for anything but
plain text.

- `-e` — interpret backslash escapes (`\n`, `\t`)

Example: `echo ""` — an empty line.

### `printf`
Prints text using a format. `%s` is a string, `%d` a number, `\n` a
newline. The format repeats for extra arguments, so `printf '%s\n' a b`
prints two lines.

Example: `printf '%s\n' "${packages[@]}"` — one package per line.

### `read`
Reads one line of input into variables.

- `-r` — keep backslashes as typed (always use it)
- `-a <array>` — split the line into an array
- `-d <delimiter>` — stop at this character instead of a newline
  (`-d ''` reads to the end of input)
- `-p <prompt>` — show a prompt first
- `-s` — do not echo what is typed (passwords)
- `-t <seconds>` — give up after this many seconds

Example: `while IFS= read -r line; do … done < "$file"` — each line.

### `mapfile`
Reads lines of input into an array.

- `-t` — drop the trailing newline of each line (always use it)
- `-O <index>` — start filling at this index (appends)

Example: `mapfile -t users < <(jq -r '.users[]?' "$profile")`

### `return`
Leaves a function with an exit status (0 = success).

Example: `return 0`

### `exit`
Ends the script with an exit status.

Example: `exit 1`

### `shift`
Drops the first argument; `$2` becomes `$1`.

Example: `shift`

### `set`
Sets shell options.

- `-e` — stop the script when a command fails
- `-u` — an unset variable is an error
- `-o <option>` — set a named option (`pipefail`: a pipeline fails when
  any part fails)
- `-E` — `ERR` traps also fire inside functions
- `-x` — print each command before running it (debugging)

Example: `set -Eeuo pipefail`

### `shopt`
Sets bash-only options.

- `-s <option>` — turn on (`nullglob`: a glob matching nothing expands
  to nothing)
- `-u <option>` — turn off

Example: `shopt -s nullglob`

### `trap`
Runs a command when the shell gets a signal or exits.

- `-p` — print the current traps

Example: `trap 'rm -rf "$temporary_directory"' EXIT`

### `cd`
Changes the current directory.

Example: `cd "$(git rev-parse --show-toplevel)"`

### `pwd`
Prints the current directory.

Example: `SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"`

### `command`
Runs a command, skipping functions of the same name.

- `-v` — print where a command is found; fails when it is missing

Example: `command -v ssh-keygen >/dev/null || skip "no ssh-keygen"`

### `compgen`
Lists completions; used here to test a glob.

- `-G <glob>` — print paths matching the glob; fails when none match

Example: `compgen -G '/etc/secrets/sops/*.json' >/dev/null`

### `continue`
Skips to the next loop iteration.

### `break`
Leaves the loop.

### `wait`
Waits for background jobs to finish.

- `-n` — wait for the next one only

Example: `wait || true`

### `kill`
Sends a signal to a process (default: ask it to stop).

- `-KILL` — stop at once; the process cannot refuse
- `-0` — send no signal: only test that the process still runs

Example: `kill "$watcher_pid" 2>/dev/null || true`

### `true`
Does nothing and succeeds.

### `false`
Does nothing and fails.

### `exec`
Replaces the shell with a command, or (with only redirections) points
the shell's own input/output somewhere else.

Example: `exec >"$log_file" 2>&1` — from here on, all output goes to the
log.

## Coreutils

GNU coreutils: the basic file and text commands. `man <name>` has the
full text.

### `cat`
Prints files one after another (or its input, with no file).

Example: `cat > "$file" <<'EOF'` — write a heredoc to a file.

### `cut`
Prints selected fields of each line.

- `-d <delimiter>` — the character between fields
- `-f <fields>` — which fields to print (`1`, `2,3`, `2-`)
- `-c <characters>` — which characters to print (`2-`: from the second on)

Example: `cut -d: -f1 /etc/passwd` — every user name.

### `head`
Prints the first lines of its input.

- `-n <count>` — how many lines (default 10)

Example: `head -n 1 "$file"` — the first line.

### `tail`
Prints the last lines of its input.

- `-n <count>` — how many lines; `-n +2` means "from line 2 on"

Example: `tail -n +2 "$csv"` — everything but the header line.

### `wc`
Counts lines, words or bytes.

- `-l` — count lines
- `-c` — count bytes

Example: `wc -l < "$file"` — just the number, no file name.

### `tr`
Replaces or deletes characters.

- `-d <characters>` — delete these characters
- `-s` — squeeze: each run of a repeated character becomes one
- `-c` — complement: act on every character NOT listed (`-dc 0-9`: keep only
  digits)

Example: `tr -d '\n'` — join all lines into one.

### `sort`
Sorts lines.

- `-u` — drop repeated lines
- `-V` — compare version numbers (`6.9` before `6.10`)
- `-n` — compare as numbers
- `-r` — reverse the order
- `-k <field>` — sort by this field (`-k2,2` = only field 2)
- `-t <separator>` — the character between fields
- `-s` — keep equal lines in input order

Example: `sort -u` — sorted, each line once.

### `uniq`
Drops repeated adjacent lines (sort first).

- `-c` — prefix each line with how often it repeated
- `-d` — print only lines that repeat (one copy each)

Example: `sort | uniq -c`

### `comm`
Compares two sorted files line by line.

- `-1`, `-2`, `-3` — hide lines only in file 1, only in file 2, in both

Example: `comm -23 wanted.txt installed.txt` — wanted but not installed.

### `basename`
Prints a path's last part.

Example: `basename /a/b/c.sh` — `c.sh`.

### `dirname`
Prints a path without its last part.

Example: `dirname /a/b/c.sh` — `/a/b`.

### `mkdir`
Creates directories.

- `-p` — create missing parents too; no error if it exists

Example: `mkdir -p "$directory"`

### `rm`
Removes files.

- `-r` — remove directories and everything in them
- `-f` — no error when the file is missing; never ask

Example: `rm -rf "$TEST_DIR"`

### `rmdir`
Removes empty directories.

Example: `rmdir "$ESP/loader/entries" "$ESP/loader"`

### `cp`
Copies files.

- `-r` — copy directories and everything in them
- `-a` — archive: like `-r`, keeping owners, modes, times and links
- `-f` — replace existing files
- `-p` — keep modes and times
- `-l` — make hard links instead of copies
- `-L` — copy what symlinks point to, not the links

Example: `cp -r "$OS/lib/." "$test_directory/lib/"`

### `mv`
Moves or renames files.

- `-f` — replace the target without asking

Example: `mv "$temporary_file" "$file"` — replace a file in one step.

### `ln`
Makes links.

- `-s` — a symbolic link (a path pointer) instead of a hard link
- `-f` — replace an existing file
- `-n` — when the target is a symlink to a directory, replace the link
  itself

Example: `ln -sf /usr/share/wayland-sessions/plasma.desktop "$target"`

### `readlink`
Prints where a symlink points.

- `-f` — follow every link and print the full real path
- `-m` — canonical path; missing parts are allowed

Example: `readlink -f ./relative`

### `install`
Copies a file and sets its mode and owner in one step; also makes
directories.

- `-d` — create directories instead of copying
- `-D` — create missing parent directories of the target
- `-m <mode>` — permission mode (`644`, `755`)
- `-o <owner>` — owner
- `-g <group>` — group

Example: `install -Dm644 "$source" "$target"`

### `chmod`
Changes permission modes.

- `-R` — also everything inside a directory

Example: `chmod +x "$TEST_DIR/bin/lsblk"`

### `chown`
Changes owners.

- `-R` — also everything inside a directory
- `-h` — change a symlink itself, not what it points to

Example: `chown -R "${USER_NAME}:${USER_NAME}" "${HOME_DIR}/.config"`

### `touch`
Creates an empty file, or updates a file's time.

Example: `touch "$marker"`

### `mktemp`
Creates a temporary file (or directory) with a unique name and prints
the name.

- `-d` — a directory
- `--suffix <text>` — end the name with this text

Example: `temporary_directory="$(mktemp -d)"`

### `tee`
Copies its input to a file and to its output.

- `-a` — append to the file

Example: `printf '%s\n' "$line" | tee -a "$log_file"`

### `date`
Prints the date and time.

- `-u` — in UTC
- `-d <date>` — this date instead of now
- `-I <precision>` — ISO 8601 form (`-Is` = to the second)

Example: `date -u +%Y%m%d-%H%M%S`

### `sleep`
Waits a number of seconds.

Example: `sleep 1`

### `timeout`
Runs a command and stops it after a time limit.

Example: `timeout 60 gamemoded -t`

### `env`
Runs a command with a changed environment.

- `-i` — start from an empty environment
- `-u <name>` — remove this variable

Example: `env -u SUDO_USER bash "$script"`

### `nohup`
Runs a command that keeps going after the terminal closes.

### `id`
Prints user and group ids.

- `-u` — the user id only
- `-g` — the group id only
- `-G` — every group id
- `-n` — names instead of numbers

Example: `id -un` — the current user's name.

### `whoami`
Prints the current user's name.

### `uname`
Prints system information.

- `-r` — the running kernel's release
- `-m` — the machine architecture (`x86_64`)

Example: `uname -r`

### `stat`
Prints file details.

- `-c <format>` — print only these fields (`%s` size, `%U` owner)

Example: `stat -c %s "$file"` — the size in bytes.

### `df`
Shows disk space per filesystem.

- `-h` — human sizes (`1.5G`)
- `-m` — sizes in MiB
- `-B <unit>` — sizes in this unit (`-B1` = bytes)
- `--output <fields>` — only these columns (`avail`, `size`)

Example: `df -h "$esp_directory"`

### `du`
Shows space used by files.

- `-s` — one total per argument
- `-h` — human sizes

### `seq`
Prints a sequence of numbers.

Example: `seq 1 5`

### `nproc`
Prints the number of CPUs.

### `truncate`
Sets a file's size.

- `-s <size>` — the size (`-s 10G`)

Example: `truncate -s 20G "$disk_image"`

### `sha256sum`
Prints SHA-256 checksums.

### `base64`
Encodes (or decodes) base64 text.

- `-w <columns>` — wrap lines at this width (`-w0` = never wrap)
- `-d` — decode

### `ls`
Lists directory contents. Prefer globs in code; `ls` is for display.

- `-A` — include hidden files, but not `.` and `..`
- `-1` — one name per line

### `hostid`
Prints the host's numeric id (ZFS uses it to own pools).

## Text tools

### `grep`
Prints lines that match a pattern. Only these flags ([ADR 0167]):

- `-q` — print nothing; the exit status says whether a line matched
- `-E` — extended regular expressions (`a|b`, `x+`, `(…)`)
- `-F` — the pattern is plain text, not a regular expression
- `-v` — print the lines that do not match
- `-x` — the whole line must match
- `-c` — print how many lines matched
- `-o` — print only the matching part of each line
- `-l` — print the names of files with a match
- `-w` — match whole words only (`docker` does not match `dockerd`)
- `-i` — ignore upper/lower case (`-qi reserved` also matches `Reserved`)

Example: `grep -qxF "$package" "$list_file"` — is this exact line in
the file?

### `sed`
Edits a file in place, one plain substitution only ([ADR 0167]):
`sed -i 's/old/new/' file`. Anything bigger goes to bash or an `.awk`
file.

- `-i` — change the file itself instead of printing

Example: `sed -i 's/^#Color/Color/' "$pacman_conf"`

### `jq`
Reads and writes JSON — the one JSON tool. Each call should be one
small, readable step ([ADR 0167]).

- `-r` — print strings without their quotes
- `-e` — fail when the result is `false` or `null`
- `-c` — print each result on one line
- `-n` — start without reading input (build JSON from `--arg`s)
- `--arg <name> <text>` — make `$name` a string inside the program
- `--argjson <name> <json>` — make `$name` a JSON value inside the
  program
- `-f <file>` — read the program from a commented `.jq` file

Example: `jq -r '.users[].name' "$profile"` — each user's name.

### `awk`
Runs an awk program. Only from an `.awk` file with a header comment and
a comment on each rule ([ADR 0167]); never inline.

- `-f <file>` — the program file
- `-v <name=value>` — set an awk variable before the program starts
- `-F <separator>` — the field separator (`-F'\t'`: tab)

Example: `awk -f "$SCANNER" -v prefix_rules="$PREFIX_RULES" "$file"`

### `diff`
Shows how two files differ.

- `-q` — only say whether they differ

Example: `diff <(registry_keys | sort) <(coverage_keys | sort)`

### `cmp`
Compares two files byte by byte.

- `-s` — print nothing; the exit status says whether they are equal

Example: `cmp -s "$doc" "$doc.linked"`

### `find`
Lists files under a directory that match tests. Its tests look like
flags but are words: `-name`, `-type`.

- `-name <glob>` — the file name matches the glob
- `-path <glob>` — the whole path matches the glob
- `-type <kind>` — `f` file, `d` directory, `l` symlink
- `-maxdepth <levels>` — go at most this deep
- `-mindepth <levels>` — skip results shallower than this
- `-not` — negate the next test
- `-print` — print the path (the default)
- `-print0` — print paths separated by NUL bytes
- `-printf <format>` — print using a format (`%P` = path under the
  start directory)
- `-quit` — stop at the first result
- `-exec <command> {} \;` — run a command per result (`{}` is the path)

Example: `find "$target/programs" -name '*.sh' -exec chmod +x {} \;`

## Shells

### `bash`
Runs a bash script (or a command string).

- `-c <command>` — run this text as the script
- `-n` — check syntax only, run nothing
- `-u` — an unset variable is an error

Example: `bash "$ADAPTER"`

### `sh`
Runs a POSIX shell script.

- `-n` — check syntax only

## bats

The test runner. `.bats` files hold `@test "name" { … }` blocks.

### `run`
Runs a command and saves its exit status in `$status` and its output in
`$output` (and line by line in `${lines[@]}`), so the test can check them.

- `--separate-stderr` — keep error output apart, in `$stderr`

Example: `run bash "$CHECK"`

### `load`
Sources a helper file next to the test (`.bash` is added).

Example: `load install-helpers`

### `skip`
Skips the current test, with a reason.

Example: `skip "ssh-keygen not available"`

### `bats_require_minimum_version`
Fails when bats is older than this version.

## Domain Tools

System commands with no coreutils or builtin substitute ([ADR 0167]).
Their used flags are listed like any other.

### `sudo`
Runs a command as root (or another user).

- `-u <user>` — run as this user
- `-E` — keep the caller's environment
- `-H` — set `HOME` to the target user's home

Example: `sudo install -o root -g root -m 644 "$file" "$target"`

### `git`
Version control. Flags below are spread over subcommands (`git status`,
`git commit`, …).

- `-C <directory>` — run as if started in this directory
- `-q` — quiet
- `-c <name=value>` — set a config value for this command only
- `-m <message>` — the commit message
- `-a` — commit every changed tracked file
- `-A` — stage every change, new files too
- `--short` — short status output
- `--show-toplevel` — print the repository's root directory
- `--name-only` — print only changed file names
- `--depth <n>` — (`clone`) fetch only the last n commits
- `--filter=<spec>` — (`clone`) skip objects, e.g. `blob:none`
- `--no-checkout` — (`clone`) do not fill the working tree
- `--sparse` — (`clone`) check out only the top-level files
- `--detach` — (`checkout`) check out a commit, not a branch
- `--allow-empty` — (`commit`) commit even with no change
- `--full-name` — (`ls-files`) print paths from the repository root
- `--verify` — (`rev-parse`) fail unless the name is a real object
- `--format=<format>` — (`log`) print each commit this way (`%ad` author date,
  `%cd` committer date)
- `--date=<form>` — (`log`) how dates print (`format-local:%F`: YYYY-MM-DD)
- `-z` — (`ls-files`, `ls-tree`) end each path with a NUL byte
- `-r` — (`ls-tree`) list subdirectories too

Example: `cd "$(git rev-parse --show-toplevel)"`

### `systemctl`
Controls systemd services.

- `--user` — the user's own service manager, not the system's
- `-P <property>` — print one property value only
- `--quiet` — print nothing; use the exit status

Example: `systemctl enable seatd`

### `pacman`
Arch's package manager.

- `-S` — install packages
- `-y` — refresh the package lists first
- `-u` — upgrade installed packages
- `-Q` — query installed packages
- `--noconfirm` — never ask
- `--needed` — skip packages already up to date
- `-q` — quiet: names only, no versions
- `-o <file>` — with `-Q`: which installed package owns the file
- `-i` — detailed info (`-Si`: the sync repo's copy, `-Qi`: the installed one)
- `-U <file>` — install a package file
- `-p` — with `-S`: print what would be installed, install nothing
- `--dbpath <directory>` — use this package database instead of the system's
- `--logfile <file>` — log here instead of `/var/log/pacman.log`
- `-Sl <repo>` — list the packages of a sync repository
- `-m` — with `-Q`: only foreign packages (not in a sync repo, e.g. AUR)
- `-l` — list a repository's packages (`-Slq`: every repo package name)

Example: `pacman -S --noconfirm --needed git`

### `zfs`
Manages ZFS datasets and snapshots.

- `-a` — all datasets (`zfs umount -a`, `zfs mount -a`)
- `-H` — no header line; fields split by tabs (for scripts)
- `-o <property=value>` — on `create` or `set`: set a property; on `list`
  or `get`: only these columns (`-o name`)
- `-t <types>` — on `list`: only these kinds (`filesystem`, `snapshot`)
- `-r` — recursive: the dataset and everything under it
- `-V <size>` — on `create`: a volume (zvol) of this size
- `-b <bytes>` — on `create -V`: the volume's block size
- `-p` — exact numbers (bytes, seconds)

Example: `zfs rollback -r "$dataset@blank"`

### `zpool`
Manages ZFS pools.

- `-f` — force
- `-H` — no header line; fields split by tabs (for scripts)
- `-o <properties>` — only these columns (`name`, `health`)
- `-P` — full device paths
- `-L` — resolve symlinks to the real device
- `-d <directory>` — on `import`: look for pool devices only here
- `-N` — on `import`: import without mounting any dataset
- `-p` — exact numbers (bytes), not human sizes

Example: `zpool export rpool || zpool export -f rpool`

### `mount`
Attaches a filesystem at a directory.

- `-o <options>` — mount options (`remount,size=2G`: resize in place)
- `-t <type>` — the filesystem type (`tmpfs`)

Example: `mount "$esp_partition" "${MOUNT_ROOT}/boot/efi"`

### `umount`
Detaches a mounted filesystem.

- `-R` — also everything mounted under it, deepest first
- `-l` — lazy: detach now, finish when no longer busy

### `lsblk`
Lists block devices (disks, partitions).

- `-n` — no header line
- `-o <columns>` — only these columns (`NAME,SIZE,FSTYPE`)
- `-d` — whole disks only, not their partitions
- `-r` — raw output: one plain line per device, no tree drawing
- `-l` — list form: one device per line, no tree

Example: `lsblk -no NAME,SIZE,FSTYPE "$device"`

### `findmnt`
Lists mounted filesystems.

- `-r` — raw output, no tree drawing
- `-n` — no header line
- `-o <columns>` — only these columns
- `-R` — this mount and everything mounted under it
- `-t <types>` — only filesystems of these types (`zfs`)
- `--target <path>` — the mount that holds this path

Example: `findmnt -rno TARGET`

### `blkid`
Prints filesystem details (UUID, type, label) of block devices.

- `-t <name=value>` — only devices with this tag (`TYPE=iso9660`)
- `-o <format>` — output form (`device` = only device paths)
- `-s <tag>` — print only this tag (`UUID`)

Example: `blkid -t TYPE=iso9660 -o device`

### `curl`
Fetches a URL.

- `-s` — silent: no progress bar
- `--max-time <seconds>` — give up after this long in total
- `--connect-timeout <seconds>` — give up connecting after this long
- `-o <file>` — save to this file instead of printing
- `-f` — fail on an HTTP error instead of saving the error page
- `-S` — with `-s`, still print errors
- `-L` — follow redirects
- `--progress-bar` — show a simple progress bar
- `--retry <count>` — try again this many times on a transient error
- `-g` — no globbing: `[]` and `{}` in the URL are plain text

Example: `curl -s --max-time 3 --connect-timeout 3 "$url"`

### `loginctl`
Shows and controls systemd-logind sessions and users.

- `--no-legend` — no header or footer lines

Example: `loginctl show-user "$SUDO_USER"` — the user's session details.

### `notify-send`
Shows a desktop notification.

- `-a <name>` — the application name shown
- `-h <hint>` — an extra hint (`string:desktop-entry:<app>` groups it
  under the app)
- `-t <milliseconds>` — how long it stays
- `-i <icon>` — the icon

Example: `notify-send -a "$app_name" -t 15000 "$title" "$message"`

### `ip`
Shows and changes network settings.

Example: `ip route show default` — fails when there is no default route.

### `timedatectl`
Shows and sets the system clock.

Example: `timedatectl set-ntp true` — keep the clock synced over the network.

### `lsmod`
Lists the loaded kernel modules.

Example: `lsmod | grep -q '^zfs '` — is the zfs module loaded?

### `zgenhostid`
Writes a random host id to `/etc/hostid` (ZFS pools record which host owns
them).

### `fzf`
An interactive fuzzy picker: reads lines, lets the operator choose, prints
the chosen lines. Drives the Guided Installer's menus.

- `--multi` — allow picking several lines (TAB marks one)
- `--reverse` — list from the top down
- `--prompt <text>` — the text before the search input
- `--header <text>` — a line shown above the list
- `--header-border <style>` — a border around the header
- `--delimiter <separator>` — what splits a line into fields
- `--with-nth <fields>` — show only these fields (the rest stay hidden but
  are still printed)
- `--preview <command>` — run this for the current line and show its
  output beside the list (`{2}` = field 2 of the line)
- `--preview-window <layout>` — where the preview sits and how wide
- `--bind <key:action>` — what a key does (`enter:accept`)
- `--border <style>` — a border around the whole picker
- `--border-label <text>` — a title on that border
- `--border-label-pos <position>` — where the title sits
- `--color <colors>` — the colour scheme
- `--pointer <text>` — the marker before the current line
- `--version` — print the version and exit

Example: `fzf --multi --reverse --delimiter='	' --with-nth=1`

### `dmesg`
Shows (and controls) the kernel's message log.

- `-n <level>` — only print messages more important than this level to
  the console (`-n 1`: silence the console)

### `arch-chroot`
Runs a command (or a shell) inside the new system's root, with `/proc`,
`/sys`, `/dev` and the ESP mounted in it.

Example: `arch-chroot "${MOUNT_ROOT}" bash /root/lib-chroot/configure.sh`

### `fuser`
Shows (or kills) the processes using a file or a mounted filesystem.

- `-k` — kill those processes
- `-m` — the argument is a mount point: every process using that
  filesystem

Example: `fuser -km "$mountpoint"` — kill whatever holds the mount busy.

### `systemd-escape`
Turns a path (or text) into the escaped form systemd uses in unit names:
`/home/user` → `home-user`.

- `-p`, `--path` — the argument is a path (drop slashes at both ends)
- `--suffix <suffix>` — add a unit suffix (`mount`, `service`)

Example: `systemd-escape --path /var/lib/docker` — `var-lib-docker`, so
the mount unit is `var-lib-docker.mount`.

### `mountpoint`
Tells whether a directory is a mount point.

- `-q` — print nothing; the exit status says it

Example: `mountpoint -q "$source_path"`

### `script`
Runs a command inside a new pseudo-terminal (a fake tty), so a program
that only reads passwords from a terminal can be fed one.

- `-q` — quiet: no start and done messages
- `-c <command>` — the command to run
- `-e` — exit with the command's exit status

Example: `printf '%s
' "$passphrase" | script -qc "age -d -o out key.age" /dev/null`

### `age`
Encrypts and decrypts files.

- `-d`, `--decrypt` — decrypt
- `-o <file>` — write the result here

Example: `age --decrypt -o "$age_key" "$encrypted_age_key"`

### `age-keygen`
Makes an age key pair.

- `-y` — print the public key of an existing private key file
- `-o <file>` — write the new key here

Example: `age-keygen -y "$key_file"`

### `sops`
Encrypts and decrypts structured secret files (JSON, YAML) with age keys.

- `-d`, `--decrypt` — decrypt to stdout
- `-e` — encrypt
- `-i` — edit the file in place
- `--yes` — answer yes to every question

Example: `SOPS_AGE_KEY_FILE="$age_key" sops --decrypt "$source"`

### `smartctl`
Reads a disk's SMART health and identity data.

- `-i` — identity: model, serial, firmware, capacity

Example: `smartctl -i "$dev"`

### `systemd-analyze`
Inspects systemd units; here, `verify` checks unit files for errors.

- `--user` — check them as user units

Example: `systemd-analyze verify "$unit_copy"`

### `ssh-keygen`
Makes and inspects SSH keys.

- `-t <type>` — the key type (`ed25519`)
- `-f <file>` — the key file
- `-N <passphrase>` — the new key's passphrase (`""`: none)
- `-C <comment>` — the comment stored in the key
- `-q` — quiet
- `-y` — print the public key of a private key file
- `-A` — make every missing host key type (in `/etc/ssh`)

Example: `ssh-keygen -t ed25519 -f "$key_file" -N "" -q`

### `ssh-to-age`
Turns an SSH ed25519 key into an age key (so the host's SSH key can
decrypt SOPS secrets).

- `-i <file>` — read this key file instead of stdin
- `-private-key` — convert the private key, not the public one

Example: `ssh-to-age < "$TEST_DIR/ssh_host_ed25519_key.pub"`

### `pvs`
Lists LVM physical volumes.

- `--noheadings` — no header line
- `-o <columns>` — only these columns (`pv_name`, `vg_name`)

Example: `pvs --noheadings -o vg_name "$physical_volume"`

### `vgremove`
Removes an LVM volume group.

- `-f` — force: no questions

### `pvremove`
Removes the LVM label from a physical volume.

- `-f` — force: no questions

### `mdadm`
Manages Linux software RAID (md) arrays.

- `--query` — say what a device is (an array, a member of one, or
  neither)
- `--stop` — stop an array

Example: `mdadm --stop "$array_device"`

### `wipefs`
Erases filesystem, RAID and partition-table signatures from a device.

- `-a` — every signature found
- `-f` — force, even on a device in use

Example: `wipefs -af "$disk"`

### `sgdisk`
Edits GPT partition tables.

- `--zap-all` — destroy the GPT and MBR tables
- `-n <number:start:end>` — create a partition (`-n2:0:+20G`: partition 2, next
  free start, 20 GiB; `0:0`: the rest of the disk)
- `-t <number:type>` — set a partition's type code (`bf00` ZFS, `ef00` ESP,
  `8200` swap)
- `-c <number:name>` — set a partition's name

Example: `sgdisk --zap-all "$disk"`

### `blkdiscard`
Tells an SSD or NVMe disk that every block is free (instant blanking).

- `-f` — force, even when the device holds a filesystem

Example: `blkdiscard -f "$disk"`

### `dd`
Copies raw bytes between files or devices. It takes `name=value`
operands, not flags: `if=` the input, `of=` the output, `bs=` the block
size, `conv=fsync` flush to disk at the end, `status=progress` report as
it goes.

Example: `dd if=/dev/zero of="$disk" bs=4M conv=fsync status=progress`

### `blockdev`
Queries and controls block devices.

- `--getsize64` — the device's size in bytes
- `--rereadpt` — make the kernel re-read the partition table

Example: `blockdev --getsize64 "$disk"`

### `setfacl`
Sets POSIX ACLs: extra per-user and per-group permissions on a file.

- `-m <entry>` — add or change an entry (`u:1000:rwx`, `d:g:100:rwx` for
  the default inherited by new files, `m::rwx` for the mask)

Example: `setfacl -m "$numeric_entry" "$target"`

### `ldd`
Lists the shared libraries a program needs and where each was found
(`not found` when it is missing).

Example: `ldd "$zpool_path" | grep -q 'not found'` — is any library missing?

### `pacman-key`
Manages pacman's keyring of trusted package-signing keys.

- `--init` — create the keyring
- `--populate <keyring>` — add a distribution's keys (`archlinux`)
- `--recv-keys <key>` — fetch a key from a keyserver
- `--keyserver <url>` — the keyserver to fetch from
- `--lsign-key <key>` — trust a key locally

Example: `pacman-key --lsign-key "$key"`

### `dkms`
Builds kernel modules from source for each installed kernel (here, ZFS
against the live ISO's kernel). Subcommands: `add`, `build`, `install`.

- `-m <module>` — the module name (`zfs`)
- `-v <version>` — the module version
- `-k <kernel>` — the kernel version to build for
- `--kernelsourcedir <directory>` — that kernel's headers

Example: `dkms install -m zfs -v "$zfs_version" -k "$kernel_version"`

### `depmod`
Rebuilds the kernel's module dependency lists.

- `-a` — for every module

### `modprobe`
Loads a kernel module and the modules it needs.

Example: `modprobe zfs`

### `modinfo`
Shows a kernel module's details.

- `-F <field>` — only this field (`version`)

Example: `modinfo -F version zfs`

### `pgrep`
Finds processes by name.

- `-x` — the whole name must match
- `-u <user>` — only this user's processes
- `-f` — match the full command line, not just the name

Example: `pgrep -x pacman` — is pacman running?

### `gdbus`
Talks to D-Bus services (here: desktop notifications).

- `--session` — the user's session bus
- `--dest <name>` — the service to call
- `--object-path <path>` — the object on it
- `--method <interface.method>` — the method to call
- `--timeout <seconds>` — give up after this long

Example: `gdbus wait --session --timeout 300 org.freedesktop.Notifications`

### `mkinitcpio`
Builds initramfs images.

- `-p <preset>` — build every image a preset names (`linux-lts`)
- `-S <hooks>` — skip these hooks (`autodetect`: a fallback image works on
  any hardware)
- `-g <file>` — write the image to this file
- `-P` — build every preset in `/etc/mkinitcpio.d`

Example: `mkinitcpio -g "${boot}/${fallback_initramfs}"`

### `swapon`
Turns swap on, or lists the swap in use.

- `--show <columns>` — list the active swap areas (`--show=NAME`: device
  names only)
- `--noheadings` — no header line

Example: `swapon --show=NAME --noheadings`

### `swapoff`
Turns a swap area off.

Example: `swapoff "$swap_device"`

### `udevadm`
Controls udev, which creates the `/dev` device nodes and links.

- `--timeout <seconds>` — with `settle`: wait at most this long

Example: `udevadm settle` — wait until udev has handled every new device.

### `getconf`
Prints a system setting.

Example: `getconf PAGESIZE` — the memory page size in bytes.

### `mkswap`
Prepares a device or file as swap.

- `-f` — force, even when it already holds something

Example: `mkswap -f "/dev/zvol/${pool_name}/swap"`

### `efibootmgr`
Lists and edits the firmware's UEFI boot entries.

- `--create` — add an entry and put it first in BootOrder
- `--create-only` — add an entry without touching BootOrder
- `--disk <disk>` — the disk holding the ESP
- `--part <number>` — the ESP's partition number
- `--label <text>` — the entry's name
- `--loader <path>` — the EFI file to boot, on the ESP (`mlinuz-linux`)
- `--unicode <options>` — the kernel command line passed to it

Example: `efibootmgr --create-only --disk "$disk" --part 1 --label "$title"`

### `mkfs.fat`
Makes a FAT filesystem (the ESP).

- `-F <bits>` — the FAT size (`-F32`: FAT32)
- `-n <label>` — the volume label

Example: `mkfs.fat -F32 "$esp_partition"`

### `mkfs.ext4`
Makes an ext4 filesystem.

- `-F` — force, even on a whole disk or a used partition
- `-L <label>` — the filesystem label

### `mkfs.xfs`
Makes an XFS filesystem.

- `-f` — force: overwrite an existing filesystem
- `-L <label>` — the filesystem label

### `mkfs.btrfs`
Makes a Btrfs filesystem, on one or several devices.

- `-f` — force: overwrite an existing filesystem
- `-d <profile>` — the data profile across devices (`raid1`, `single`)
- `-m <profile>` — the metadata profile
- `-L <label>` — the filesystem label

Example: `mkfs.btrfs -f -d raid1 -m raid1 "${devices[@]}"`

### `partprobe`
Tells the kernel to re-read a disk's partition table.

Example: `partprobe "$disk"`

### `cryptsetup`
Sets up LUKS-encrypted block devices. Subcommands: `luksFormat` (make
one), `open` (unlock it as `/dev/mapper/<name>`), `close`.

- `--type <type>` — the LUKS version (`luks2`)
- `--batch-mode` — no questions
- `--key-file <file>` — read the key from this file, not a prompt

Example: `cryptsetup open "$part" "$mapper" --key-file "$keyfile"`

### `btrfs`
Manages Btrfs filesystems. Subcommands used: `subvolume create`,
`subvolume snapshot`, `device scan`, `filesystem show`.

- `-r` — (`subvolume snapshot`) make the snapshot read-only

Example: `btrfs subvolume create "${MOUNT_ROOT}/${subvol}"`

### `bootctl`
Installs and manages systemd-boot on the ESP. Subcommand used: `install`.

- `--esp-path=<dir>` — where the ESP is mounted

Example: `bootctl --esp-path="$ESP" install`

### `grub-install`
Installs GRUB's boot loader files onto the ESP and registers it.

- `--target=<platform>` — the platform (`x86_64-efi`)
- `--efi-directory=<dir>` — where the ESP is mounted
- `--boot-directory=<dir>` — where GRUB keeps its files
- `--bootloader-id=<name>` — the boot entry name
- `--removable` — install to the fallback path `EFI/BOOT`
- `--recheck` — re-probe the devices

Example: `grub-install --target=x86_64-efi --efi-directory="$ESP"`

### `refind-install`
Installs the rEFInd boot manager onto the ESP.

- `--root <dir>` — the root the system is installed in

Example: `refind-install --root /`

### `rsync`
Copies a directory tree, sending only what changed.

- `-a` — archive: recurse and keep permissions, times, links
- `--delete` — remove files at the target that the source lacks

Example: `rsync -a --delete /boot/efi/ "/boot/efi${i}/"`

### `hwclock`
Reads or sets the hardware (RTC) clock.

- `--systohc` — set the hardware clock from the system clock

Example: `hwclock --systohc`

### `locale-gen`
Builds the locales enabled in `/etc/locale.gen`.

Example: `locale-gen`

### `getent`
Prints entries from the system databases (`passwd`, `group`, …). Exits
non-zero when the entry is missing.

Example: `getent group seat >/dev/null`

### `useradd`
Creates a user account.

- `-m` — create the home directory
- `-s <shell>` — the login shell
- `-G <groups>` — extra groups, comma-separated

Example: `useradd -m -s "$LOGIN_SHELL" -G "$groups" "$NAME"`

### `usermod`
Changes an existing user account.

- `-a` — with `-G`: add to the groups, keep the others
- `-G <groups>` — extra groups, comma-separated
- `-s <shell>` — the login shell
- `-c <comment>` — the comment (full name) field
- `--add-subuids <first-last>` — give a range of sub-UIDs
- `--add-subgids <first-last>` — give a range of sub-GIDs

Example: `usermod -aG seat greeter`

### `groupadd`
Creates a group.

Example: `groupadd docker`

### `chpasswd`
Sets passwords from `user:password` lines on stdin.

Example: `printf '%s:%s
' "$NAME" "$PASSWORD" | chpasswd`

### `chsh`
Changes a user's login shell.

- `-s <shell>` — the new login shell

Example: `chsh -s "$ROOT_SHELL" root`

### `visudo`
Edits or checks sudoers files safely.

- `-c` — check syntax only
- `-f <file>` — the file to check

Example: `visudo -c -f "$SUDOERS_FILE"`

### `systemd-detect-virt`
Tells whether the system runs in a VM or container.

- `--vm` — only VMs, not containers
- `--quiet`, `-q` — print nothing; use the exit status

Example: `systemd-detect-virt --vm --quiet`

### `systemd-id128`
Prints 128-bit IDs (machine ID, boot ID). Subcommand used: `new`.

Example: `systemd-id128 new`

### `systemd-machine-id-setup`
Writes `/etc/machine-id` when it is missing.

- `--root=<dir>` — the root to write in

Example: `systemd-machine-id-setup --root="$ROOT"`

### `systemd-tmpfiles`
Creates the files and directories a `tmpfiles.d` config lists.

- `--create` — create the listed files and directories

Example: `systemd-tmpfiles --create /etc/tmpfiles.d/nix-store.conf`

### `busctl`
Talks to D-Bus. Subcommands used: `status` (who owns a bus name).

- `--user` — the user bus, not the system bus

Example: `busctl --user status org.freedesktop.FileManager1`

### `setsid`
Runs a program in a new session, detached from the terminal.

- `-f` — always fork, so it returns at once

Example: `setsid -f teamspeak3`

### `pkill`
Signals processes by name.

- `-f` — match the full command line, not only the name

Example: `pkill -f ts3client`

### `logrotate`
Rotates log files as its config says.

- `-d` — debug: show what would be done, change nothing

Example: `logrotate -d "$LOGROTATE_CONF"`

### `openssl`
Crypto toolkit. Subcommand used: `rand` (random bytes).

- `-hex` — (`rand`) print the bytes as hex

Example: `openssl rand -hex 32`

### `paccache`
Removes old packages from pacman's cache.

- `-r` — remove the old packages
- `-k <n>` — keep the n newest versions of each package

Example: `paccache -rk "$keep"`

### `pkgfile`
Finds which package owns a file. `-u` refreshes its database.

- `-u` — update the file database

Example: `pkgfile -u`

### `go`
The Go toolchain. Subcommand used: `install`.

Example: `go install "$module@latest"`

### `npx`
Runs a package from the npm registry without installing it.

- `--yes`, `-y` — answer yes to install prompts
- `-g` — (skills CLI) install globally
- `-s <skill>` — (skills CLI) which skills to add
- `-a <agent>` — (skills CLI) which agent to install for

Example: `npx --yes skills@latest add mattpocock/skills`

### `ufw`
The Uncomplicated Firewall. Subcommands used: `default`, `allow`,
`limit`, `enable`, `reset`, `status`.

- `--force` — no confirmation prompt

Example: `ufw default deny incoming`

### `firewall-offline-cmd`
Configures firewalld while it is not running.

- `--zone=<zone>` — the zone to change
- `--add-service=<service>` — allow a service
- `--add-interface=<interface>` — put an interface in the zone
- `--add-masquerade` — NAT traffic leaving the zone
- `--direct` — pass a raw iptables rule (with `--add-rule`)
- `--add-rule` — add the raw rule that follows
- `-s <subnet>` — (in a raw rule) match this source subnet
- `-j <target>` — (in a raw rule) what to do on a match

Example: `firewall-offline-cmd --zone="$ZONE" --add-service=dhcp`

### `rkhunter`
Rootkit Hunter: scans for rootkits and changed system files.

- `--update` — update its data files
- `--propupd` — record the current file properties as the baseline
- `--check` — run the scan
- `--sk` — skip the "press Enter" pauses
- `--nocolors` — plain output
- `--quiet`, `-q` — print nothing but warnings

Example: `rkhunter --check --sk --nocolors`

### `clamscan`
ClamAV's standalone virus scanner.

- `-r` — scan directories recursively
- `-i` — print infected files only
- `--no-summary` — no summary at the end

Example: `clamscan -r -i --no-summary "$SCAN_DIR"`

### `clamdscan`
Scans files through the running ClamAV daemon.

- `--fdpass` — pass the open file to the daemon (no read rights needed)
- `--no-summary` — no summary at the end

Example: `clamdscan --fdpass --no-summary "$file"`

### `freshclam`
Downloads ClamAV's virus database.

Example: `freshclam`

### `borg`
BorgBackup. Subcommands used: `init`, `create`, `list`.

- `-e <mode>` — the encryption mode of a new repository (`repokey`)

Example: `borg init -e repokey "$directory/repo"`

### `podman`
Runs containers without a daemon. Subcommands used: `run`, `pull`,
`info`.

Example: `podman run --rm "$image" true`

### `lp`
Sends a file to a printer queue. Prints the job ID.

- `-d <queue>` — the printer queue

Example: `lp -d fa-audit`

### `lpadmin`
Adds or changes CUPS printer queues.

- `-p <queue>` — the queue to add or change
- `-x <queue>` — delete this queue
- `-E` — enable the queue and accept jobs
- `-v <uri>` — the printer address
- `-m <model>` — the driver (`everywhere` = driverless IPP)

Example: `lpadmin -p fa-audit -E -v "$uri" -m everywhere`

### `lpstat`
Shows CUPS printers and jobs.

- `-o <queue>` — list the jobs of this queue
- `-W <which>` — which jobs (`completed`)
- `-l` — long listing

Example: `lpstat -W completed -o fa-audit`

### `ippeveprinter`
A fake IPP printer for tests.

- `-r <mode>` — DNS-SD advertising (`off`)
- `-p <port>` — the port to listen on
- `-f <types>` — the document types it accepts

Example: `ippeveprinter -r off -p 8631 fa-audit`

### `powerprofilesctl`
Reads or sets the power profile. Subcommands used: `get`, `set`.

Example: `powerprofilesctl get`

### `hyprctl`
Controls a running Hyprland.

- `-j` — print JSON

Example: `hyprctl -j configerrors`

### `kreadconfig6`
Reads one key from a KDE config file.

- `--file <file>` — the config file to read
- `--group <group>` — the `[group]` the key is in
- `--key <key>` — the key to read

Example: `kreadconfig6 --file "$file" --group General --key Name`

### `wl-copy`
Copies stdin to the Wayland clipboard.

Example: `printf 'text' | wl-copy`

### `xdg-user-dir`
Prints the path of a user directory (`DESKTOP`, `DOWNLOAD`, …).

Example: `xdg-user-dir DOWNLOAD`

### `noctalia-greeter-apply-appearance`
Copies the Noctalia appearance to the greeter.

- `--setup-system` — the system-wide first setup

Example: `noctalia-greeter-apply-appearance --setup-system`

### `codium`
VSCodium, the editor.

- `--list-extensions` — print installed extension IDs
- `--install-extension <id>` — install one extension

Example: `codium --list-extensions`

### `emacs`
The Emacs editor.

- `--daemon=<name>` — start as a background server with this socket name

Example: `emacs --daemon="$socket"`

### `emacsclient`
Sends a command to a running Emacs daemon.

- `-s <name>` — the server socket to talk to
- `-e <expression>` — evaluate this Lisp expression

Example: `emacsclient -s "$socket" -e "(kill-emacs)"`

### `nvim`
The Neovim editor.

- `--headless` — run with no user interface
- `-c <command>` — run this Ex command after loading

Example: `nvim --headless -c 'qa'`

### `zsh`
The Z shell. Its flags end at the script name.

- `-i` — interactive: read `.zshrc`
- `-c <command>` — run this command

Example: `zsh -i -c 'exit'`

### `paste`
Joins lines. With `-s`, all of a file's lines become one line.

- `-s` — join all lines into one
- `-d <delimiter>` — put this between them, not a tab

Example: `printf '%s
' "${countries[@]}" | paste -sd,` — `DE,FR`.

### `reflector`
Picks the fastest Arch mirrors and writes a pacman mirrorlist.

- `--latest <n>` — only the n most recently synced mirrors
- `--sort <key>` — order them by this (`rate`: download speed)
- `--save <file>` — write the mirrorlist here
- `--country <list>` — only mirrors in these countries (comma-separated)

Example: `reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist`

### `repo-add`
Adds package files to a local pacman repository database.

Example: `repo-add "$dir/pin.db.tar.zst" "$dir/linux-lts-6.18.52-1-x86_64.pkg.tar.zst"`

### `su`
Runs a command as another user. `su - <user>` starts a login shell, so the
user's own environment is used.

- `-c <command>` — run this command (in the user's shell)

Example: `su - "$user" -c 'paru --version'`

### `tar`
Packs or unpacks archives.

- `-x` — extract
- `-C <directory>` — work in this directory

Example: `git archive HEAD~1 | tar -x -C "$temporary"` — unpack a tree.

### `lspci`
Lists the PCI devices (graphics cards, network cards, …).

- `-nn` — show the vendor:device numbers next to the names (`[8086:1912]`)

Example: `lspci -nn`

### `localectl`
Queries the system locale and keyboard settings. Subcommands used:
`list-keymaps`, `list-locales`.

Example: `localectl list-keymaps`

### `cfdisk`
An interactive, full-screen disk partitioner.

Example: `cfdisk "$disk"`

### `cksum`
Prints a checksum and the byte count of its input (coreutils): a short
fingerprint of a text.

Example: `printf '%s\n' "$config" | cksum | cut -d' ' -f1` — the
checksum alone.

### `gunzip`
Unpacks gzip-compressed input.

Example: `curl -fsSL "$url" | gunzip` — the unpacked download.

<!-- ADR links: generated by readability.sh --fix-adr-links -->
[ADR 0167]: ../docs/adr/0167-coreutils-first-tool-reference.md
