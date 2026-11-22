# Crosswalk between two frames of a scale

Materialises the `from -> leaves -> to` route as a table: one row per
pair of overlapping members with

## Usage

``` r
scale_map(x, source, target, weight = NULL, by = character(), ...)
```

## Arguments

- x:

  The
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  the frames belong to.

- source, target:

  Frame names of `x`.

- weight:

  Weight column for `w`. `NULL` uses the default weight; when the object
  declares no weights at all, every leaf gets weight 1 (an equal split).

- by:

  Extra identifier columns carried through from
  [`scale_leaf_pairs()`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaf_pairs.md)
  (e.g. `"year"`).

- ...:

  Passed to
  [`scale_leaf_pairs()`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaf_pairs.md).

## Value

A `data.frame` with columns `<from>`, `<to>` (`NA` = uncovered by
`target`), `n_from`, `n_overlap`, `w`, `w_from`, plus any `by` columns.

## Details

- `n_from` – leaves in the `source` member (its full set, before any
  target coverage is considered),

- `n_overlap` – leaves the pair shares,

- `w` – the weight of the overlap (summed leaf weights, chosen weight
  column), the quantity `"weighted_mean"` aggregation uses,

- `w_from` – the full weight of the `source` member; `w / w_from` is the
  split share `"sum"` disaggregation uses.

The two label columns are named by the frames; rows with an `NA` target
label are leaves `target` does not cover. A crosswalk registered with
[`register_scale_map()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_map.md)
is returned as-is instead of being derived.

## See also

[`scale_map_between()`](https://optimal2050.github.io/nestedscales/r/reference/scale_map_between.md)
for the map between two scales.

## Examples

``` r
s <- scale_example()
scale_map(s, "class", "group")
#>   class group n_from n_overlap   w w_from
#> 1    G1    G1      2         2 300    300
#> 2    G2    GB      2         2 700    700
#> 3    S1    GB      2         1 500   1100
#> 4    S1    GC      2         1 600   1100
scale_map(s, "sector", "class", weight = "count")
#>   sector class n_from n_overlap   w w_from
#> 1      P    G1      4         2 100    200
#> 2      P    G2      4         2 100    200
#> 3      S    S1      2         2 100    100
```
