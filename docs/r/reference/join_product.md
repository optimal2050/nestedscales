# Attach every axis's labels to product-indexed data

**\[experimental\]** This feature may change or be removed in a later
version.

[`join_scale()`](https://optimal2050.github.io/nestedscales/r/reference/join_scale.md)
applied to each axis in turn, keyed by that axis's column. Because every
attached column is named after its scale, the result carries all the
axes' labels side by side.

## Usage

``` r
join_product(data, x, axes = NULL, ...)
```

## Arguments

- data:

  The data, carrying one key column per axis.

- x:

  A
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

- axes:

  Axis names to attach; `NULL` (default) attaches all of them.

- ...:

  Passed to
  [`join_scale()`](https://optimal2050.github.io/nestedscales/r/reference/join_scale.md)
  (`attach`, `meta`, `as_factor`, ...).

## Value

`data` with each axis's labels attached, in its own class.

## Examples

``` r
p <- scale_product(a = scale_example(), b = scale_example2())
d <- data.frame(item = c("U1", "U3"), period = c("p1", "p2"), v = 1:2)
join_product(d, p, attach = TRUE)
#>   item period v example.sector example.class example.group example example2.era
#> 1   U1     p1 1              P            G1            G1      U1           E1
#> 2   U3     p2 2              P            G2            GB      U3           E1
#>   example2
#> 1       p1
#> 2       p2
```
