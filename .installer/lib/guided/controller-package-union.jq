# controller-package-union.jq — the package names one category offers (ADR
# 0058), each once, sorted: the effective view's, the baseline's, and the
# excluded ones the baseline declares there (so they can be re-checked).
#
# Run with -n. Arguments: $e the effective config, $b the baseline config,
# $s the slot (repo/aur), $k the category.

# The baseline's packages in the category.
($b.packages[$s][$k] // []) as $baseline

# The excluded packages the baseline declares in the category.
| [($e.packages.exclude // [])[] | select(. as $x | $baseline | index($x))]
  as $excluded

# All three lists joined, each name once, one per line.
| ($e.packages[$s][$k] // []) + $baseline + $excluded
| unique | .[]
