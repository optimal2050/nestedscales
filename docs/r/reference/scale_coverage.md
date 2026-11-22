# Coverage of a sampled NestedScale

The fraction of the root parent's weight that survives in this object. A
scale that was never subset covers all of itself, so every weight
reports 1.

## Usage

``` r
scale_coverage(x, weight = NULL)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- weight:

  A single weight name, or `NULL` for all declared weights.

## Value

A named numeric over the declared weights, or a single unnamed numeric
when `weight` is given.

## Examples

``` r
scale_coverage(scale_example())
#>  size count 
#>     1     1 
```
