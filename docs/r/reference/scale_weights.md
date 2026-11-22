# Weight columns of a NestedScale

Weight columns of a NestedScale

## Usage

``` r
scale_weights(x)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

## Value

A character vector of weight column names (possibly empty).

## Examples

``` r
scale_weights(scale_example())
#> [1] "size"  "count"
```
