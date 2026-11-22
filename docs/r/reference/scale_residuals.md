# Members that are residuals

A residual carries a real value but is not a destination for allocation:
non-regionalized GDP, taxes that belong to no industry, an "n.e.c."
bucket. It aggregates upward like any other member – that is the point,
it is what makes the parent total reconcile – but
[`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md)
never splits a coarse figure INTO one.

## Usage

``` r
scale_residuals(x, frame = NULL)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- frame:

  A single frame name for just that frame's residuals, or `NULL` for the
  whole named list.

## Value

A character vector of member codes, or the named list over frames. Empty
when the scale declares none.

## Details

Declare them when building the scale, per frame, because codes are not
unique across frames:
`scale_from_leaftable(..., residuals = list(item = "DE_XR"))`.

## Examples

``` r
s <- scale_example()
scale_residuals(s) # none declared
#> list()

lf <- scale_leaftable(s)
r <- scale_from_leaftable(
  lf,
  frames = scale_frames(s), leaf = "item",
  weights = scale_weights(s), name = "with_residual",
  residuals = list(item = "OTH")
)
scale_residuals(r, "item")
#> [1] "OTH"
```
