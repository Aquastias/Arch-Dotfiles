#!/usr/bin/env bash
# =============================================================================
# lib/configs-generator.sh — Per-program Config Generator
# =============================================================================
# Public API:
#   cg_validate_manifest <manifest-path>
#   cg_resolve_variants  <programs_root> <variants_json>
#   cg_build_plan        <programs_root> <resolved_json> <stow_root>
#   cg_detect_conflicts  <plan_json> <legacy_root> <legacy_packages>
#   cg_materialize       <plan_json>
#
# See .scratch/per-program-config-tree/PRD.md and ADR 0012.
# =============================================================================

# shellcheck source=./jsonc.sh
source "${BASH_SOURCE[0]%/*}/jsonc.sh"

cg_validate_manifest() {
  local manifest="$1"
  [[ -f "$manifest" ]] || return 1
  jsonc_strip "$manifest" \
    | jq -e '
        (.files | type) == "array"
        and all(.files[]; (.src | type) == "string"
                          and (.dst | type) == "string")
      ' >/dev/null
}

cg_resolve_variants() {
  local root="$1" variants="$2"
  local out='{}' errors=0
  local prog_dir prog cat have_default name picked vd vbase
  local -a variant_dirs

  for prog_dir in "$root"/*/*; do
    [[ -d "$prog_dir" ]] || continue
    prog="$(basename "$prog_dir")"
    cat="$(basename "$(dirname "$prog_dir")")"

    have_default=0
    variant_dirs=()
    for vd in "$prog_dir"/configs "$prog_dir"/configs@*; do
      [[ -d "$vd" ]] || continue
      vbase="$(basename "$vd")"
      [[ "$vbase" == 'configs@*' ]] && continue
      if [[ "$vbase" == "configs" ]]; then
        [[ -f "$vd/manifest.jsonc" ]] || continue
        have_default=1
        continue
      fi
      name="${vbase#configs@}"
      if [[ "$name" == "default" ]]; then
        printf 'error: %s: configs@default/ is reserved; use configs/\n' \
          "$cat/$prog" >&2
        errors=1
        continue
      fi
      if ! [[ "$name" =~ ^[a-z0-9-]+$ ]]; then
        printf 'error: %s: variant dir %q violates [a-z0-9-]+\n' \
          "$cat/$prog" "$vbase" >&2
        errors=1
        continue
      fi
      [[ -f "$vd/manifest.jsonc" ]] || continue
      variant_dirs+=("$name")
    done

    (( have_default == 0 && ${#variant_dirs[@]} == 0 )) && continue

    picked="$(jq -r --arg p "$prog" '.[$p] // empty' <<<"$variants")"

    if [[ -z "$picked" || "$picked" == "default" ]]; then
      if (( have_default == 1 )); then
        out="$(jq -c --arg k "$cat/$prog" \
          '. + {($k): "configs"}' <<<"$out")"
      else
        if [[ -z "$picked" ]]; then
          printf 'error: %s: only configs@*/ exist; declare variants["%s"]\n' \
            "$cat/$prog" "$prog" >&2
        else
          printf 'error: %s: variants["%s"] = "default" but no configs/\n' \
            "$cat/$prog" "$prog" >&2
        fi
        errors=1
      fi
      continue
    fi

    local found=0
    for vd in "${variant_dirs[@]}"; do
      [[ "$vd" == "$picked" ]] && { found=1; break; }
    done
    if (( found == 1 )); then
      out="$(jq -c --arg k "$cat/$prog" --arg v "configs@$picked" \
        '. + {($k): $v}' <<<"$out")"
    else
      printf 'error: %s: variants["%s"] = "%s" but configs@%s/ not found\n' \
        "$cat/$prog" "$prog" "$picked" "$picked" >&2
      errors=1
    fi
  done

  printf '%s\n' "$out"
  return "$errors"
}

cg_build_plan() {
  local root="$1" resolved="$2" stow_root="$3"
  local plan='[]' prog variant prog_dir manifest entries
  while IFS=$'\t' read -r prog variant; do
    [[ -n "$prog" ]] || continue
    prog_dir="$root/$prog/$variant"
    manifest="$prog_dir/manifest.jsonc"
    entries="$(jsonc_strip "$manifest" \
      | jq -c --arg base "$prog_dir" --arg stow "$stow_root" '
          [ .files[] | {
              src_abs: ($base + "/" + .src),
              dst_in_stow_tree: ($stow + (.dst | sub("^~/"; "/"))),
              mode: (.mode // null)
            } | with_entries(select(.value != null)) ]
        ')"
    plan="$(jq -c --argjson a "$plan" --argjson b "$entries" \
      -n '$a + $b')"
  done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<<"$resolved")
  printf '%s\n' "$plan"
}

cg_detect_conflicts() {
  printf '[]\n'
}

cg_materialize() {
  local plan="$1"
  local src dst mode
  while IFS=$'\t' read -r src dst mode; do
    [[ -n "$src" ]] || continue
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
    [[ -z "$mode" || "$mode" == "null" ]] || chmod "$mode" "$dst"
  done < <(jq -r '.[] | [.src_abs, .dst_in_stow_tree, (.mode // "")]
                       | @tsv' <<<"$plan")
}
