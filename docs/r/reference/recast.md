# Recast data through a scale

The bare pipeline verb, dispatching on the scale so one entry point
serves a
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md),
a
[`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md),
and the dimension subclasses in `timescales` and `geoscales`, which
register their own methods against this generic.
[`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md)
and
[`recast_product()`](https://optimal2050.github.io/nestedscales/r/reference/recast_product.md)
are the explicit workers.

## Usage

``` r
recast(x, scale, ...)
```

## Arguments

- x:

  The data to recast.

- scale:

  The scale to recast through.

- ...:

  Passed to the dispatched method: for a
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  the arguments of
  [`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md),
  with `target` the target frame and `source` the source frame (inferred
  when omitted); for a
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md)
  those of
  [`recast_product()`](https://optimal2050.github.io/nestedscales/r/reference/recast_product.md).

## Value

The recast data, in the input's class.

## Details

The scale is `scale`; the source frame is `source` and the target
`target`, as in
[`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md),
so a call reads the same through the generic and through the worker.

## Examples

``` r
s <- scale_example()
d <- data.frame(
  item = c("U1", "U2", "U3", "U4", "U5", "U6"),
  capacity = c(1, 2, 3, 4, 5, 6)
)
recast(d, s, target = "sector", rule = "sum")
#>   sector capacity
#> 1      P       10
#> 2      S       11
```
