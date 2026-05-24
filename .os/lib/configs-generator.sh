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
  local manifest="$1" json errors=0 dir
  if [[ ! -f "$manifest" ]]; then
    printf 'error: %s: not a file\n' "$manifest" >&2
    return 1
  fi
  dir="$(dirname "$manifest")"

  if ! json="$(jsonc_strip "$manifest" | jq -c '.' 2>/dev/null)"; then
    printf 'error: %s: malformed JSONC\n' "$manifest" >&2
    return 1
  fi

  if ! jq -e 'type == "object"' <<<"$json" >/dev/null; then
    printf 'error: %s: top level must be an object\n' "$manifest" >&2
    return 1
  fi

  local extra
  extra="$(jq -r 'keys - ["files"] | .[]' <<<"$json")"
  if [[ -n "$extra" ]]; then
    while IFS= read -r k; do
      printf 'error: %s: unknown top-level key %q\n' "$manifest" "$k" >&2
    done <<<"$extra"
    errors=1
  fi

  if ! jq -e '(.files | type) == "array"' <<<"$json" >/dev/null; then
    printf 'error: %s: missing or non-array "files"\n' "$manifest" >&2
    return 1
  fi

  local count i entry src dst mode entry_extra expanded
  count="$(jq '.files | length' <<<"$json")"
  for (( i=0; i<count; i++ )); do
    entry="$(jq -c ".files[$i]" <<<"$json")"

    if ! jq -e 'type == "object"' <<<"$entry" >/dev/null; then
      printf 'error: %s [%d]: entry must be an object\n' "$manifest" "$i" >&2
      errors=1
      continue
    fi

    entry_extra="$(jq -r 'keys - ["src","dst","mode"] | .[]' <<<"$entry")"
    if [[ -n "$entry_extra" ]]; then
      while IFS= read -r k; do
        printf 'error: %s [%d]: unknown key %q\n' "$manifest" "$i" "$k" >&2
      done <<<"$entry_extra"
      errors=1
    fi

    src="$(jq -r '.src // empty' <<<"$entry")"
    dst="$(jq -r '.dst // empty' <<<"$entry")"
    mode="$(jq -r '.mode // empty' <<<"$entry")"

    if [[ -z "$src" ]]; then
      printf 'error: %s [%d]: missing src\n' "$manifest" "$i" >&2
      errors=1
    elif [[ ! -f "$dir/$src" ]]; then
      printf 'error: %s [%d]: src %q not found under %s\n' \
        "$manifest" "$i" "$src" "$dir" >&2
      errors=1
    fi

    if [[ -z "$dst" ]]; then
      printf 'error: %s [%d]: missing dst\n' "$manifest" "$i" >&2
      errors=1
    else
      [[ "$dst" == "~/"* ]] || {
        printf 'error: %s [%d]: dst %q must start with ~/\n' \
          "$manifest" "$i" "$dst" >&2
        errors=1
      }
      [[ "/$dst/" == *"/../"* ]] && {
        printf 'error: %s [%d]: dst %q contains .. segment\n' \
          "$manifest" "$i" "$dst" >&2
        errors=1
      }
      expanded="${dst/#\~\//$HOME/}"
      if [[ "$expanded" == */etc/* || "$expanded" == /etc/* ]]; then
        printf 'error: %s [%d]: dst expands under /etc/ (%s)\n' \
          "$manifest" "$i" "$expanded" >&2
        errors=1
      fi
      if [[ "$expanded" == */usr/* || "$expanded" == /usr/* ]]; then
        printf 'error: %s [%d]: dst expands under /usr/ (%s)\n' \
          "$manifest" "$i" "$expanded" >&2
        errors=1
      fi
    fi

    if [[ -n "$mode" ]] && ! [[ "$mode" =~ ^0?[0-7]{3,4}$ ]]; then
      printf 'error: %s [%d]: mode %q not octal (0?[0-7]{3,4})\n' \
        "$manifest" "$i" "$mode" >&2
      errors=1
    fi
  done

  return "$errors"
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
        if [[ ! -f "$vd/manifest.jsonc" ]]; then
          printf 'error: %s: configs/ missing %s\n' \
            "$cat/$prog" "$vd/manifest.jsonc" >&2
          errors=1
          continue
        fi
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
      if [[ ! -f "$vd/manifest.jsonc" ]]; then
        printf 'error: %s: configs@%s/ missing %s\n' \
          "$cat/$prog" "$name" "$vd/manifest.jsonc" >&2
        errors=1
        continue
      fi
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
