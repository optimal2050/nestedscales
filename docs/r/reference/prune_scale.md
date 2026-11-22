# Collapse a NestedScale to a coarser frame

Returns a new
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
whose leaf layer is `frame`, dropping every finer frame. Weights are
summed over the collapsed leaves.

## Usage

``` r
prune_scale(x, frame)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- frame:

  The frame to become the new leaf layer.

## Value

A
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

## Details

The result is renamed `"name@frame"` with the parent recorded in
`meta$parent_name`; every other meta field is preserved. Leaves with no
code at `frame` are dropped, and that loss is reflected in
`meta$coverage`. The concrete class is kept: a subclass comes back as
itself, its attribute and alias rows at the surviving frames kept, and a
positional payload merged through
[`scale_payload_collapse()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_collapse.md).

## Examples

``` r
prune_scale(scale_example(), "class")
#> NestedScale: example@class
#> Description: Synthetic example: reused code, non-nesting frame pair, and an unassigned leaf 
#> Frames (2, coarsest first):
#>   - sector (2)
#>     - class (3)
#> Leaves: 3
#> Weights: size, count (default: size)
```
