#!/usr/bin/env bash
# =============================================================================
# lib/config/categorized-list.sh — Categorized List Parser
# =============================================================================
# Pure function over JSON. No I/O, no state.
#
# Used by host package lists (packages.repo, packages.aur) and DE adapter
# lists (apps_list, aur) to validate a 2-level { category: leaves } shape
# and flatten to a sorted-unique list at install time.
#
# Requires: jq, lib/common.sh (for error()).
# =============================================================================

# Kebab-case category names: lowercase letters, digits, hyphens. No leading
# or trailing hyphen; no consecutive hyphens.
_CL_CAT_RE='^[a-z0-9]+(-[a-z0-9]+)*$'

# categorized_list_parse JSON LEAF_TYPE [FIELD_PATH]
#   JSON       — JSON string. Two-level: { category: <leaves> }.
#   LEAF_TYPE  — "string" (leaves are arrays of strings) or
#                "bool"   (leaves are objects of { name: bool }).
#   FIELD_PATH — Optional path used in error messages (e.g. "packages.repo").
#                Defaults to "<root>".
#
# Prints sorted-unique flat list on stdout, one item per line:
#   string mode → every string leaf, deduped.
#   bool mode   → every key whose value is true, deduped.
#
# Aborts via error() (exit 1) on shape, leaf-type, or category-name violations.
categorized_list_parse() {
  local json="$1" leaf_type="$2" field_path="${3:-<root>}"

  case "$leaf_type" in
    string|bool) ;;
    *) error "categorized_list_parse: leaf_type must be 'string' or 'bool'," \
             "got '${leaf_type}'." ;;
  esac

  local top_type
  top_type="$(printf '%s' "$json" | jq -r 'type')"
  if [[ "$top_type" != "object" ]]; then
    error "${field_path}: expected object, got ${top_type}."
  fi

  local want_cat_type want_leaf
  if [[ "$leaf_type" == "string" ]]; then
    want_cat_type="array"
    want_leaf="string"
  else
    want_cat_type="object"
    want_leaf="boolean"
  fi

  local key got_type
  while IFS=$'\t' read -r key got_type; do
    if ! [[ "$key" =~ $_CL_CAT_RE ]]; then
      error "${field_path}.${key}: invalid category name" \
            "(expected kebab-case ${_CL_CAT_RE})."
    fi
    if [[ "$got_type" != "$want_cat_type" ]]; then
      error "${field_path}.${key}: expected ${want_cat_type}," \
            "got ${got_type}."
    fi
  done < <(printf '%s' "$json" \
    | jq -r 'to_entries[] | "\(.key)\t\(.value | type)"')

  local cat leaf_path lkey ltype
  if [[ "$leaf_type" == "string" ]]; then
    while IFS=$'\t' read -r cat leaf_path ltype; do
      if [[ "$ltype" != "$want_leaf" ]]; then
        error "${field_path}.${cat}${leaf_path}: expected ${want_leaf} leaf," \
              "got ${ltype}."
      fi
    done < <(printf '%s' "$json" \
      | jq -r '
          to_entries[] as $c
          | $c.value | to_entries[]
          | "\($c.key)\t[\(.key)]\t\(.value | type)"
        ')
  else
    while IFS=$'\t' read -r cat lkey ltype; do
      if [[ "$ltype" != "$want_leaf" ]]; then
        error "${field_path}.${cat}.${lkey}: expected ${want_leaf} leaf," \
              "got ${ltype}."
      fi
    done < <(printf '%s' "$json" \
      | jq -r '
          to_entries[] as $c
          | $c.value | to_entries[]
          | "\($c.key)\t\(.key)\t\(.value | type)"
        ')
  fi

  if [[ "$leaf_type" == "string" ]]; then
    printf '%s' "$json" \
      | jq -r '[.[][]] | unique[]'
  else
    printf '%s' "$json" \
      | jq -r '
        [ to_entries[] | .value | to_entries[] | select(.value == true) | .key ]
        | unique[]
      '
  fi
}
