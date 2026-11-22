# Realise the leaves of a product

**\[experimental\]** This feature may change or be removed in a later
version.

The cross product of the component leaftables: one row per tuple of
component leaves, with each axis's key column named by
[`product_keys()`](https://optimal2050.github.io/nestedscales/r/reference/product_keys.md)
and its frame columns prefixed `"<axis>."`.

## Usage

``` r
product_leaves(x, limit = 1e+06)
```

## Arguments

- x:

  A
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

- limit:

  Maximum number of rows to build. Exceeding it is an error that reports
  the size, rather than a very long wait.

## Value

A `data.frame` with `product_size(x)$total` rows.

## Details

This is guarded on purpose. An hourly calendar crossed with NUTS3 is
~12.9M rows; the whole point of a product is that its leaves exist
implicitly, and conversion never needs them realised (see
[`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md)).
Ask for them only when you actually want the grid.

## Examples

``` r
p <- scale_product(a = scale_example(), b = scale_example2())
head(product_leaves(p))
#>   item a.sector a.class a.group period b.era
#> 1   U1        P      G1      G1     p1    E1
#> 2   U2        P      G1      G1     p1    E1
#> 3   U3        P      G2      GB     p1    E1
#> 4   U4        P      G2      GB     p1    E1
#> 5   U5        S      S1      GB     p1    E1
#> 6   U6        S      S1      GC     p1    E1
```
