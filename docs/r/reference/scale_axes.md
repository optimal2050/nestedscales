# Axes of a product

**\[experimental\]** This feature may change or be removed in a later
version.

## Usage

``` r
scale_axes(x, axis = NULL)
```

## Arguments

- x:

  A
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

- axis:

  Optional single axis name, to get just that
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

## Value

A named list of
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
objects, or one NestedScale when `axis` is given.

## Examples

``` r
p <- scale_product(a = scale_example(), b = scale_example2())
names(scale_axes(p))
#> [1] "a" "b"
scale_axes(p, "a")
#> NestedScale: example
#> Description: Synthetic example: reused code, non-nesting frame pair, and an unassigned leaf 
#> Frames (4, coarsest first):
#>   - sector (2)  [1 member unassigned]
#>     - class (3)  [1 member unassigned]
#>       - group (3)  [1 member unassigned]
#>         - item (7)
#> Leaves: 7
#> Weights: size, count (default: size)
```
