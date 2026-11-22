# Are the members of a frame the same size?

`TRUE` when every member of `frame` holds the same number of leaves, or
the same total of a weight column: the dimension-free form of a
"regular" calendar (equal durations) or an equal-area regionalisation.
Leaves with no code at `frame` are ignored.

## Usage

``` r
scale_is_uniform(x, frame, weight = NULL, tolerance = 1e-09)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- frame:

  A frame name.

- weight:

  `NULL` compares leaf counts; a weight column name compares its
  per-member totals.

- tolerance:

  Relative tolerance for weight totals.

## Value

A logical scalar. When `FALSE`, the attribute `"sizes"` holds the
per-member counts or totals.

## Examples

``` r
s <- scale_example()
scale_is_uniform(s, "class")                  # two leaves each
#> [1] TRUE
scale_is_uniform(s, "class", weight = "size") # but not the same size
#> [1] FALSE
#> attr(,"sizes")
#>   G1   G2   S1 
#>  300  700 1100 
```
