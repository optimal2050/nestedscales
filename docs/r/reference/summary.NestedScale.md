# Summarize a NestedScale

Complements [`print()`](https://rdrr.io/r/base/print.html) with the
quantitative view: per-weight totals and coverage, and the
adjacent-frame nesting table. Returns a `"summary_Scale"` object (a
list) with its own print method.

## Usage

``` r
# S3 method for class 'NestedScale'
summary(object, ...)

# S3 method for class '`nestedscales::NestedScale`'
summary(object, ...)

# S3 method for class 'summary_Scale'
print(x, ...)
```

## Arguments

- object:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- ...:

  Ignored.

- x:

  A `"summary_Scale"` object (the print method's argument).

## Value

[`summary()`](https://rdrr.io/r/base/summary.html) returns a list of
class `"summary_Scale"`: `name`, `desc`, `frames` (named member counts),
`unassigned` (named NA-leaf counts), `n_leaves`, `weights`,
`weight_totals`, `default_weight`, `coverage` (see
[`scale_coverage()`](https://optimal2050.github.io/nestedscales/r/reference/scale_coverage.md)),
`sampled`, `parent_name`, `nesting` (adjacent-pair table with offender
counts, see
[`scale_nests()`](https://optimal2050.github.io/nestedscales/r/reference/scale_nests.md)),
`attributes` (a `data.frame` of row counts by `attribute`, `frame` and
`source`), `aliases` (counts by `source`), `labels` (counts by `frame`
and `variant`), `source`, `vocab`.

## Examples

``` r
summary(scale_example())
#> <summary of NestedScale 'example'>
#>   desc:          Synthetic example: reused code, non-nesting frame pair, and an unassigned leaf
#>   frames:         sector (2) / class (3) / group (3) / item (7)
#>   leaves:         7
#>   unassigned:     sector (1), class (1), group (1)
#>   weight totals:  size = 3,100, count =   300  (default: size)
#>   nesting:        sector > class: nested
#>   nesting:        class > group: CROSS-CUTTING (1 offender(s))
#>   nesting:        group > item: nested
```
