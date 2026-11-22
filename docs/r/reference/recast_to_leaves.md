# Recast member data down to the leaf layer, and back

The two public halves of the `from -> leaves -> to` route:
`recast_to_leaves()` projects member-keyed data DOWN to the leaf layer
(one row per leaf), and `recast_from_leaves()` aggregates leaf-keyed
data UP into a frame's members. Their composition is
[`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md),
and because the leaf rows are keyed by the leaf codes,
`recast_from_leaves(recast_to_leaves(data, a), b, target)` recasts
across two scales that share leaf codes.

## Usage

``` r
recast_to_leaves(
  data,
  x,
  source = NULL,
  key = NULL,
  values = NULL,
  rule = NULL,
  weight = NULL,
  attach_weight = TRUE,
  collect = NULL
)

recast_from_leaves(
  data,
  x,
  target,
  key = NULL,
  values = NULL,
  rule = NULL,
  weight = NULL,
  na_rm = FALSE,
  na_action = c("drop", "error", "keep"),
  collect = NULL
)
```

## Arguments

- data:

  The data: for `recast_to_leaves()` keyed by member code at frame
  `source`; for `recast_from_leaves()` keyed by leaf codes.

- x:

  The
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  the data is keyed in, or aggregated into.

- source:

  `to_leaves` only: frame name the codes belong to. `NULL` (default) is
  inferred as in
  [`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md).

- key:

  The key column; defaults as in
  [`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md).

- values, rule:

  As in
  [`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md).

- weight:

  `to_leaves`: a declared weight column of `x`. `from_leaves`: the name
  of a column of `data` to weight by, so the weight may vary by
  identifier. `NULL` uses a `weight` column of the data if present, else
  the scale's declared weight.

- attach_weight:

  `to_leaves` only: attach the `weight` column (default `TRUE`).

- collect:

  For lazy inputs: materialise (`TRUE`) or return the query.

- target:

  `from_leaves` only: target frame name.

- na_rm:

  `from_leaves` only: read an `NA` value as "this member says nothing"
  rather than as an unknown that makes the whole group `NA`.

- na_action:

  `from_leaves` only: what to do with leaves that have no code at
  `target`.

## Value

`recast_to_leaves()`: one row per (leaf x identifier combination).
`recast_from_leaves()`: one row per (member x identifier combination).
Both in the input's class; lazy in, lazy out.

## Details

Going down, extensive columns (rule `"sum"`) are split across a member's
leaves proportionally to the chosen weight so totals conserve; intensive
columns are repeated. A `weight` column is attached by default so the
return trip's `"weighted_mean"` reproduces the source weighting exactly.

## Examples

``` r
s <- scale_example()
d <- data.frame(sector = c("P", "S"), capacity = c(10, 20))
leaves <- recast_to_leaves(d, s,
  source = "sector", rule = "sum",
  weight = "size"
)
head(leaves)
#>   item  capacity weight
#> 1   U1  1.000000    100
#> 2   U2  2.000000    200
#> 3   U3  3.000000    300
#> 4   U4  4.000000    400
#> 5   U5  9.090909    500
#> 6   U6 10.909091    600
recast_from_leaves(
  leaves, s,
  target = "class",
  rule = "sum",
  na_action = "keep"
)
#>   class capacity
#> 1    G1        3
#> 2    G2        7
#> 3    S1       20
#> 4  <NA>       NA
```
