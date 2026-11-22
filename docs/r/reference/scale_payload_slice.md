# Subset a subclass's per-leaf payload

The seam a dimension package overrides when it carries per-leaf data
alongside the leaftable – geoscales' `Geoscale` and its geometry. Called
whenever the engine rebuilds an object from a row subset, with the kept
row indices. The `NestedScale` default has no payload and returns `x`
unchanged.

## Usage

``` r
scale_payload_slice(x, ...)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- ...:

  Method arguments: `i`, the integer vector of kept leaftable row
  indices.

## Value

`x`, with any payload subset to the kept rows.

## Examples

``` r
identical(
  scale_payload_slice(scale_example(), 1:3),
  scale_example()
)
#> [1] TRUE
```
