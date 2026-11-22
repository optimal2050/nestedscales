# The leaftable of a NestedScale

The one-row-per-leaf table the scale is built on, as a plain
`data.frame` – the exported accessor to prefer over reaching for
`x@leaftable`.
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) and
[`ggplot2::fortify()`](https://ggplot2.tidyverse.org/reference/fortify.html)
on a NestedScale are equivalent, so `ggplot(s) + geom_*()` pipelines
work directly.

## Usage

``` r
scale_leaftable(x)

# S3 method for class 'NestedScale'
as.data.frame(x, row.names = NULL, optional = FALSE, ...)

# S3 method for class '`nestedscales::NestedScale`'
as.data.frame(x, row.names = NULL, optional = FALSE, ...)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- row.names, optional:

  Ignored (S3 signature compatibility).

- ...:

  Ignored.

## Value

A `data.frame`: one row per leaf, with the frame columns plus any weight
columns.

## Examples

``` r
head(scale_leaftable(scale_example()))
#>   sector class group item size count
#> 1      P    G1    G1   U1  100    10
#> 2      P    G1    G1   U2  200    90
#> 3      P    G2    GB   U3  300    30
#> 4      P    G2    GB   U4  400    70
#> 5      S    S1    GB   U5  500    50
#> 6      S    S1    GC   U6  600    50
head(as.data.frame(scale_example()))
#>   sector class group item size count
#> 1      P    G1    G1   U1  100    10
#> 2      P    G1    G1   U2  200    90
#> 3      P    G2    GB   U3  300    30
#> 4      P    G2    GB   U4  400    70
#> 5      S    S1    GB   U5  500    50
#> 6      S    S1    GC   U6  600    50
```
