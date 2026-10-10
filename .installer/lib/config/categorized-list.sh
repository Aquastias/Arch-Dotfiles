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
_CATEGORIZED_LIST_CATEGORY_PATTERN='^[a-z0-9]+(-[a-z0-9]+)*$'

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

  local want_category_type want_leaf
  if [[ "$leaf_type" == "string" ]]; then
    want_category_type="array"
    want_leaf="string"
  else
    want_category_type="object"
    want_leaf="boolean"
  fi

  _categorized_list_check_categories "$json" "$field_path" "$want_category_type"
  _categorized_list_check_leaves "$json" "$field_path" "$leaf_type" "$want_leaf"

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

# _categorized_list_check_categories <json> <field-path> <want-type> — abort
# (error) on a non-kebab-case category name or a category of the wrong type.
_categorized_list_check_categories() {
  local json="$1" field_path="$2" want_category_type="$3" key got_type
  while IFS=$'\t' read -r key got_type; do
    if ! [[ "$key" =~ $_CATEGORIZED_LIST_CATEGORY_PATTERN ]]; then
      error "${field_path}.${key}: invalid category name" \
            "(expected kebab-case ${_CATEGORIZED_LIST_CATEGORY_PATTERN})."
    fi
    if [[ "$got_type" != "$want_category_type" ]]; then
      error "${field_path}.${key}: expected ${want_category_type}," \
            "got ${got_type}."
    fi
  done < <(printf '%s' "$json" \
    | jq -r 'to_entries[] | "\(.key)\t\(.value | type)"')
}

# _categorized_list_check_leaves <json> <field-path> <leaf-type> <want-leaf>
# — abort (error) on a leaf that is not <want-leaf>. A string leaf is named
# by its index (`.cat[0]`), a bool leaf by its key (`.cat.name`).
_categorized_list_check_leaves() {
  local json="$1" field_path="$2" leaf_type="$3" want_leaf="$4"
  local category leaf_path got_type
  while IFS=$'\t' read -r category leaf_path got_type; do
    if [[ "$got_type" != "$want_leaf" ]]; then
      error "${field_path}.${category}${leaf_path}: expected ${want_leaf}" \
            "leaf, got ${got_type}."
    fi
  done < <(printf '%s' "$json" \
    | jq -r --arg mode "$leaf_type" '
        to_entries[] as $c
        | $c.value | to_entries[]
        | "\($c.key)\t"
          + (if $mode == "string" then "[\(.key)]" else ".\(.key)" end)
          + "\t\(.value | type)"
      ')
}
