# Subset a NestedScale

`x[frame, member]` is
[`filter_scale()`](https://optimal2050.github.io/nestedscales/r/reference/filter_scale.md).

## Usage

``` r
# S3 method for class 'NestedScale'
x[i, j, ...]

# S3 method for class '`nestedscales::NestedScale`'
x[i, j, ...]
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- i:

  Frame name.

- j:

  Member codes to keep.

- ...:

  Unused.

## Value

A
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

## Examples

``` r
scale_example()["sector", "P"]
#> NestedScale: example[sector:P]
#> Description: Synthetic example: reused code, non-nesting frame pair, and an unassigned leaf 
#> Frames (4, coarsest first):
#>   - sector (1)
#>     - class (2)
#>       - group (2)
#>         - item (4)
#> Leaves: 4
#> Weights: size, count (default: size)
```
