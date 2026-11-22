# Leaf-level correspondence between two frames

The seam a dimension package overrides when its leaf layer is generated
rather than enumerated. Returns one row per leaf (or per leaf and extra
identifier, e.g. per grid instant and year).

## Usage

``` r
scale_leaf_pairs(x, ...)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- ...:

  Method arguments: `source` and `target` (frame names of `x`), `weight`
  (a weight column, or `NULL` for the scale's default), and whatever
  else the dimension needs to generate its leaves – `year` for a
  calendar.

## Value

A `data.frame` with columns `source`, `target`, `w`, plus any extra
identifier columns the dimension carries. The extra columns must be
named in the `by` argument of the caller.

## Examples

``` r
head(scale_leaf_pairs(scale_example(), "class", "group"))
#>   source target   w
#> 1     G1     G1 100
#> 2     G1     G1 200
#> 3     G2     GB 300
#> 4     G2     GB 400
#> 5     S1     GB 500
#> 6     S1     GC 600
```
