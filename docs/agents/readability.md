# Readability

How installer (`.installer/`) code is named, sized, and structured so its owner
can read it after months away ([ADR 0153]). Every change — human or agent —
follows these rules. The Readability Lint enforces the mechanical ones; the
rest are on you. Comments follow [comment-style.md](comment-style.md).

## Flow first

- Each entry script opens with a `main()` near the top that calls phase
  functions only — it reads as the script's table of contents.
- Each lib file header carries a `Used by:` line naming the scripts/libs that
  source it.
- `ARCHITECTURE.md` links to the `main()`s instead of restating the flow.

## Names

- **No abbreviations.** Spell words out: `password` not `pw`, `encryption` not
  `enc`, `config` not `cfg`, `directory` not `dir`, `navigation` not `nav`.
  Allowed short tokens: domain acronyms (`zfs esp gpu aur iso vm ssh uid luks
  tty`, plus standard ones like `os id ip json url uuid`), command names used
  as words (`jq mv cp rm ln`), and small English words.
- **Locals** name their content (`dataset`, `profile_path`). Only `i`/`j`
  (numeric loop counters) and `rc` (exit status) may be short.
- **Prefix.** A function's Prefix names the file that defines it
  (`config/history.sh` → `history_`). A directory exposing one public API lends
  its name to public functions (`feature_audit_`); private ones use
  `_<file stem>_`. A leading `_` means file-private. The full Prefix Map is
  below.
- **Name shape.**
  - Actions: `<prefix>_<verb>_<object>` — `pools_create_root`.
  - Predicates: `<prefix>_is_/has_/can_…` — return a status, print nothing.
  - Producers (print a value): named for what they print —
    `guided_effective_value`.
- **Interface Functions** — one name implemented once per backend, the sourced
  module answering — take their glossary role name, not a file Prefix:
  `root_adapter_*` (Root Layout Adapter), `data_formatter_*` (Data Group
  Formatter).
- **Globals** are declared together at the top of their file with a one-line
  meaning: `UPPER_SNAKE` when shared, `_MODULE_UPPER` when file-private.

## Size

- Files ≤ 500 lines — split by responsibility; each new file gets its own
  Prefix.
- Functions ≤ ~50 lines and ≤ 3 levels of `if`/`for`/`while`/`case`
  nesting — split when you touch one that exceeds it.

## Tool Tiers

One tool per job. Never trade readability for one fewer binary.

- **Core:** bash builtins, `jq` (all JSON), `awk` (any multi-field or
  multi-step text work), `grep` (filtering), `sort`, file ops (`mkdir cp mv rm
  ln find mktemp`).
- **`sed`:** in-place edits (`sed -i`) only; other transforms go to `awk`.
- **Replace:** `cut tr head tail wc paste comm uniq column bc xargs realpath`
  → a core tool or builtin (`mapfile`, `${#array[@]}`, `printf`). Symlinks
  have one tool, `readlink` (`readlink -f` canonicalises — `realpath`'s job).
  `basename`/`dirname` → `parent_directory` / `base_name`, defined in every
  Commons world (Installer Stdlib, chroot common, Shell Stdlib). A
  self-contained lib that cannot source its world's stdlib (it is sourced
  alone, e.g. `picker.sh`, `impermanence-common.sh`) uses `${path##*/}` or a
  private helper instead. Before any stdlib is sourced — a script locating its
  own directory — strip the name with `"${BASH_SOURCE[0]%/*}"`, but guard a
  path with no slash first (`bash 03-install.sh` would otherwise `cd` into the
  file name):

  ```bash
  script_path="${BASH_SOURCE[0]}"
  [[ "$script_path" == */* ]] || script_path="./$script_path"
  SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"
  ```
- Merge consecutive `jq` reads of one input into one program when the result
  stays short or is factored with named `def`s.

## Frozen

Never renamed by readability work: host-profile JSON keys, CLI flags, env vars
read from outside `.installer/`, paths written on the target, and any string a
test, audit, or Known Noise pattern greps for. Renames touching a domain term
update `CONTEXT.md` first; ADRs are never edited for renames.

## Readability Lint

`.installer/tests/readability.sh` (scanner: `readability-scan.awk`; run by
`readability.bats` in the suite) reports `rule: file:line: detail` for:

| Rule | Catches |
| --- | --- |
| `function-name` | abbreviated token in a function name |
| `local-name` | abbreviated / single-letter `local`, `declare`, or `for` var |
| `function-length` | function over 50 lines (heredoc bodies not counted: data) |
| `nesting` | keyword nesting deeper than 3 |
| `file-length` | file over 500 lines |
| `tool` | a replace-tier tool at command position |
| `sed-not-inplace` | `sed` without `-i` |
| `prefix` | a function name not starting with its file's Prefix |
| `adr-link` | an `ADR NNNN` in a doc that is not a link |

The allow/deny token lists live in the scanner's `BEGIN` block — extend them
there. Only code is scanned: quoted text, comments, and heredoc bodies are
skipped, as are program `home/` payloads.

**Strict.** Any violation fails the lint — new code must be clean. (The
Readability Baseline ratchet that eased the lint in shrank to zero and was
removed.)

- `readability.sh --list` prints every violation without failing.
- `readability.sh --fix-adr-links` links every ADR mention in the docs in
  place: `ADR 0058` becomes the shortcut link `[ADR 0058]`, resolved by a
  generated definition block at the end of the file (two extra characters,
  changed lines rewrapped to 80). Docs in scope: tracked Markdown minus
  `.scratch/`, vendored `.agents/skills/`, and program payloads. Code
  comments keep the plain `(ADR NNNN)` anchor.

**Escape hatch.** A line containing `readability-ok: <reason>` is exempt; on a
function's opening line it exempts the whole function. Use it for genuine
exceptions (a `head` that cuts a stream on purpose), never to dodge a rename.

## Prefix Map

**Status: applied.** The lint's `prefix` rule reads
the map's exceptions from `.installer/tests/readability-prefixes.txt` (every
other file takes its stem).

### Rules behind the map

1. **File stem.** Public `<stem>_`, private `_<stem>_` (`-` → `_`).
2. **Directory API.** A directory whose files serve one public API lends its
   name to every public function; private ones keep `_<stem>_`. Directory APIs:
   `feature-audit/` → `feature_audit_`, `guided/` → `guided_`, `layout/` →
   `layout_`, `matrix/` → `matrix_`, `wipe/` → `wipe_`, `zfs/` → `zfs_`,
   `vm/lib/` → `vm_`.
3. **Rename the file, not the functions,** when its functions already share a
   readable name (`accessors.sh` holds `install_config_*` →
   `install-config.sh`).
4. **Exempt from a Prefix** (names must still be words):
   - executables, never sourced — entry scripts, `install.sh`, `tools/*.sh`,
     `vm/vm.sh`, `vm/vm-agent.sh`, `tests/*.sh`, program `scripts/`;
   - the stdlibs — `lib/common.sh`, `lib/chroot/chroot-common.sh`,
     `lib/chroot/extras-common.sh`, `lib/shell/*.sh` — they are the base
     vocabulary (`info`, `confirm`, `parent_directory`);
   - a function named exactly its stem (`jsonc`, `finalize`);
   - bats files (test-local helpers);
   - files defining no functions (program `install.sh` scripts, staged
     chroot steps like `configure.sh`, DM adapters);
   - frozen external contracts: mkinitcpio hook API (`run_hook`,
     `run_latehook`, `build`, `help`).
5. **Interface Functions** keep one shared name across backends (below).
6. **Stem clash** (two files, same stem, both public): qualify with the
   parent directory. Private clashes are harmless.

### Interface Functions

- Layout interface (Layout Module / Root Layout Adapter, already in
  `CONTEXT.md`): `layout_validate`, `layout_plan`, `layout_partition`,
  `layout_create_pools`, `layout_mount_esp`; hooks `_layout_plan_mode`,
  `_layout_os_disks`, `_layout_publish_boot` — names kept.
- Root filesystem hooks: `_root_mkfs` → `root_adapter_mkfs`, `_root_fstype`
  → `root_adapter_fstype`.
- Data Group Formatter: `_data_mkfs` → `data_formatter_mkfs`,
  `data_group_create` → `data_formatter_create_group`.
- VM flow (one flow sourced per run): `flow_run`, `_flow_build_seed`,
  `_flow_render_user_data` — names kept.
- Feature Audit probes (`programs/*/*/audit.sh`, `extras/**/audit*.sh`):
  `_fa_*` → `_probe_*`.

### Stdlib renames (words, no Prefix)

- `cfg` → `config_required`, `cfgo` → `config_optional` (Installer Stdlib).
- `lib/preflight.sh` `command_exists` twin → kept (preflight runs before
  `common.sh` is sourced); exempt in `readability-prefixes.txt`.
- `lib/packages/kernel.sh` `error` fallback → kept (chroot loaders source it
  without `common.sh`); exempt in `readability-prefixes.txt`.

### Per file

Format: `file`: today → public / private. `=` means unchanged.

lib/
- `aur-helper.sh`: `_aur_`, `_profiles_` → `aur_helper_` / `_aur_helper_`
- `chroot.sh`: `write_*`, `configure_system`, `collect_passwords`,
  `apply_impermanence`, `_chroot_`, `_resolve_` → `chroot_` / `_chroot_`
- `finalize.sh`: `finalize`, `_finalize_` → `=`
- `globals.sh`: `layout_*` accessors → move to `layout/state.sh`, names kept
- `grub-common.sh`: `_grub_` → `_grub_common_`
- `impermanence-common.sh`: `imp_`, `persist_` → `impermanence_common_`
- `install-state.sh`, `jsonc.sh`, `picker.sh`, `prompt.sh`, `secrets.sh`,
  `preflight.sh` → `=`
- `live-medium.sh`: `_lm_`, `is_live_medium`, `live_medium_` →
  `live_medium_` / `_live_medium_`

lib/boot/
- `bootloaders.sh` → rename `bootloader.sh`; `bootloader_` kept
- `esp-budget.sh`: `esp_` → `esp_budget_`
- `esp-kernel-sync.sh`: `esp_` → `esp_kernel_sync_`
- `esp-stage.sh`: `esp_` → `esp_stage_`
- `loader-entries.sh`: `sdboot_entry`, `grub_entry`, … →
  `loader_entries_<bootloader>` (`loader_entries_systemd_boot`)
- `lts-hold.sh`: `lts_`, `_lts_` → `lts_hold_`
- `stray-kernel.sh`: `stray_` → `stray_kernel_`
- `vm-video.sh`: `vm_` → `vm_video_`
- `lsm.sh`, `zswap.sh` → `=`

lib/chroot/ (Chroot Configuration Modules; per-file stems)
- `base-services.sh`: `enable_*_services` → `base_services_`
- `bootloader-common.sh`: `blcommon_`, `_bl_` → `bootloader_common_`
- `create-user.sh`: `filter_existing_groups` → `create_user_`
- `gpu.sh`: `_gpu_` → `=` (private only)
- `impermanence.sh`: `_impermanence_`, `_imp_` → `_impermanence_`; hook API
  frozen
- `initcpio.sh`: `_initcpio_` → `=`; hook API frozen
- `noctalia-preset.sh`: `noctalia_`, `_noc_` → `noctalia_preset_`
- `udisks.sh` → `=`
- `zfs-import.sh`: `zfs_import_`, `zfs_write_` → `zfs_import_`

lib/config/ (per-file stems)
- `accessors.sh` → rename `install-config.sh`; `install_config_` kept
- `categorized-list.sh`: `categorized_` → `categorized_list_`
- `config-apply.sh`: `ca_` → `config_apply_` (`ca_stow_opt_in_list` →
  `config_apply_stow_opted_in_programs`)
- `edits.sh` → rename `edit.sh`; `edit_` kept
- `emit.sh`: `guided_*_delta`, `guided_user_profile`, `emit_effective` →
  `emit_`
- `environment.sh`: `resolve_environment`, `print_environment_summary`,
  `_resolve_env_`, `_gpu_` → `environment_` / `_environment_`
- `history.sh`: `hist_` → `history_`
- `layer-resolver.sh`: `layer_` → `layer_resolver_`
- `layers.sh` (program registry) → rename `program-registry.sh`;
  `program_registry_`
- `lifecycle.sh`: `load_config`, `detect_mode`, `print_summary` →
  `lifecycle_`
- `locale-parts.sh`: `locale_` → `locale_parts_`
- `locale-source.sh`: `locale_` → `locale_source_`
- `manual-partition.sh`: `manual_` → `manual_partition_`
- `menu-owned.sh`: `*_owned_programs`, `menu_owned_` → `menu_owned_`
- `nav.sh` → rename `navigation.sh`; `nav_` → `navigation_`, the screen
  words spelled out (`nav_to_pkgcat` → `navigation_to_package_category`); the
  screen strings in the nav JSON stay as-is
- `post-install.sh`: `post_` → `post_install_`
- `profile.sh` (Profile Loader) → rename `profile-loader.sh`;
  `profile_loader_`
- `seed.sh` + `state.sh` (`cfgstate_`) → merge into `config-state.sh`;
  `config_state_`
- `store.sh` (`cfgstore_`) → rename `config-store.sh`; `config_store_`
- `validation.sh`: `validate_`, `_validation_` → `validation_`; its program
  contracts split out to `validation-programs.sh`, kept on `validation_` by
  a `file` rule
- `bluetooth.sh`, `display.sh`, `fonts.sh`, `menu.sh`, `mirrors.sh`,
  `power.sh`, `printing.sh`, `profiles.sh`, `skeleton.sh`, `timezone.sh` → `=`

lib/feature-audit/ (directory API `feature_audit_`)
- public `fa_` → `feature_audit_`; private `_fa_` → `_<stem>_`
  (`_live_`, `_binds_`, `_binds_guest_`, `_check_`, `_report_`,
  `_manifest_`, `_probe_lib_`)
- `live.sh` split into `live.sh` + `live-phases.sh`, `live-probes.sh`,
  `live-keybinds.sh`, `live-run.sh` — one `file` rule (`live*.sh`) keeps
  them on `_live_`; the `FA_*` env namespace stays frozen

lib/guided/ (directory API `guided_`)
- `controller.sh`: `_ctl_` → `_controller_` (split first, ticket 15)
  — split into `controller.sh` + `controller-*.sh` (fields, user-fields,
  chrome, screen-data, detail, list, enter-users/host/values/pools,
  history); one `file` rule (`controller*.sh`) puts them on `_controller_`
- `shell.sh`: `_guided_` → `_guided_shell_` (`_shell_` would read as the
  Shell Stdlib); split into `shell.sh` + `shell-assembly.sh`,
  `shell-options.sh`, `shell-users.sh`, `shell-session.sh` — one `file`
  rule (`shell*.sh`) keeps them all on `_guided_shell_`
- `mask.sh`, `rows.sh`, `save.sh`, `secrets.sh`, `secrets-file.sh`,
  `userforms.sh`, `fzf-entry.sh` (`_entry_` → `_fzf_entry_`) → `guided_`

lib/layout/ (directory API `layout_`, plus Interface Functions)
- `core.sh`: `_layout_` → `_core_`; `parse_size_to_*`, `nonzfs_plan_field`
  → `layout_`
- `data-pools.sh`: `resolve_data_pools`, … → `layout_` / `_data_pools_`
- `dispatch.sh`: `root_adapter_source`, … → `=`
- `zfs/multi.sh`: `suggest_*`, `resolve_*`, `create_multi_*`, … → `layout_`
  / `_zfs_multi_`
- `zfs/single.sh`: `calculate_single_disk_layout`, … → `layout_` /
  `_zfs_single_`
- `nonzfs/root.sh`: `_nzroot_`, `_nonzfs_` → `_nonzfs_root_`
- `nonzfs/*.sh`, `btrfs/*.sh`, `manual/*.sh`: public → `layout_`; private
  `_<fs>_<stem>_` (`_btrfs_subvol_`, `_manual_plan_`)

lib/matrix/ (directory API `matrix_`)
- private `_matrix_` → `_<stem>_`; `pairwise.sh` `_pw_` → `_pairwise_`

lib/packages/ (per-file stems)
- `archive.sh`: `kver_to_pkgver`, `pkg_*` → `archive_`
- `archzfs-kernel.sh`: `archzfs_`, `_archzfs_`, `_mirror_` →
  `archzfs_kernel_`
- `filesystem.sh`: `fs_`, `luks_userland_packages` → `filesystem_`
- `list.sh` → rename `package-list.sh`; `package_list_`
- `niri.sh`: `niri_core_packages` stays `niri_`; the Noctalia functions
  (shared with Hyprland) move to a new `noctalia.sh` → `noctalia_`
- `resolver.sh` (Package Resolver) → rename `package-resolver.sh`;
  `pkgres_` → `package_resolver_`; its desktop/Noctalia sets split out to
  `package-resolver-desktop.sh`, kept on `package_resolver_` by a `file`
  rule
- `list.sh`'s host pacman.conf edits split out to `pacman-config.sh` →
  `pacman_config_` (its `[options]` awk program in `pacman-options.awk`)
- `audio.sh`, `base.sh`, `gpu.sh`, `iso-resolver.sh`, `kernel.sh`,
  `microcode.sh` → `=`

lib/profiles/
- `runner.sh` (Runner): `_profiles_`, `run_`, `resolve_` → `runner_` /
  `_runner_`

lib/wipe/ (directory API `wipe_`)
- `teardown_*`, `run_parallel_wipe`, `progress_*` → `wipe_`; private
  `_<stem>_` (`run_parallel_wipe` → `wipe_run_parallel`, `progress_pct` →
  `wipe_progress_percent`, `_progress_si` → `_progress_humanize`)

lib/zfs/ (directory API `zfs_`)
- `pools.sh`: `install_zfs_tools_if_needed`, `ram_gib`,
  `collect_enc_passphrase`, `build_*`, … → `zfs_` / `_pools_`
- `pool-owners.sh`: `pool_`, `_pool_` → `zfs_pool_owners_` /
  `_pool_owners_`
- `module.sh`, `verify.sh`: `zfs_` kept; private `_<stem>_`

vm/lib/ (directory API `vm_`)
- `core.sh`: `_vm_`, `_ensure_`, … → `_core_`; `core_resolve_iso` →
  `vm_resolve_iso`
- `console-answerer.sh`, `host-capacity.sh`, `profile.sh`,
  `profile-validate.sh`, `seed-generator.sh`, `sentinel-watcher.sh`,
  `esp-resilience-verify.sh`: public → `vm_<stem>_`, private `_<stem>_`
- `flow-persistent.sh` split into `flow-persistent.sh` +
  `flow-persistent-run.sh`; `seed-generator.sh` into `seed-generator.sh` +
  `seed-generator-firstboot.sh` — one `file` rule per pair
  (`flow-persistent*.sh`, `seed-generator*.sh`) keeps each on `vm_` /
  `_<stem>_`
- `agent-commands.sh` (new): `vm-agent.sh`'s pure helpers; a `file` rule
  (`agent-*.sh`) keeps them on `agent_` / `_agent_`; agent verbs stay
  frozen
- `vm-pool-verify.sh`: `vm_pool_*` → `=`

extras/desktop/ (Desktop Environment Adapters)
- `hyprland/hyprland.sh`: `_hypr_` → `_hyprland_`
- `kde/kde.sh`: `_seed_write`, `link` → `_kde_`

tests/lib/
- `aur-vet.bash`: `aurvet_` → `aur_vet_`; `validators.bash` → `=`
- bats files over 500 lines split into `<stem>-<part>.bats` parts that
  `load <stem>-helpers`; the shared `*-helpers.bash` (bats `setup`,
  `teardown`, stubs) is prefix-exempt

<!-- ADR links: generated by readability.sh --fix-adr-links -->
[ADR 0153]: ../../docs/adr/0153-human-readable-installer-code.md
