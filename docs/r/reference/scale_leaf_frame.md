# The frame whose members are the leaves

The finest frame when one code of it sits on each leaftable row, and the
leaf column otherwise. A
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
built from a nested hierarchy is the first kind; a timescales `Calendar`
is the second, because its timeslices are combinations of its frames
rather than codes of any one of them.

## Usage

``` r
scale_leaf_frame(x)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

## Value

A single string: the name of the frame whose members are the leaves, or
of the leaf column when no frame is.

## Details

Needed by the dimension packages: it is the `frame` to pass to
[`join_scale()`](https://optimal2050.github.io/nestedscales/r/reference/join_scale.md)
or
[`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md)
for data keyed at the leaves.

## Examples

``` r
scale_leaf_frame(scale_example())
#> [1] "item"
```
