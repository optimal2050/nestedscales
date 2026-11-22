# Do two frames form a product?

`TRUE` when every member of `a` combines with the same set of members of
`b`, as the months and hours of a `MONTH x HOUR` calendar do: the frames
overlay rather than nest, and the leaves are their combinations. The
complement of
[`scale_nests()`](https://optimal2050.github.io/nestedscales/r/reference/scale_nests.md)
for the other common shape; a pair can be neither.

## Usage

``` r
scale_crosses(x, a, b)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- a, b:

  Frame names.

## Value

A logical scalar. When `FALSE`, the attribute `"offenders"` names the
members of `a` whose set of `b` members differs from the first one's.

## Examples

``` r
s <- scale_example()
scale_crosses(s, "class", "group")
#> [1] FALSE
#> attr(,"offenders")
#> [1] "G2" "S1"

grid <- expand.grid(m = c("m1", "m2"), h = c("h1", "h2", "h3"),
                    stringsAsFactors = FALSE)
grid$item <- paste(grid$m, grid$h, sep = "_")
mh <- scale_from_leaftable(grid, frames = c("m", "h"), leaf = "item")
scale_crosses(mh, "m", "h")
#> [1] TRUE
scale_nests(mh, "m", "h")
#> [1] FALSE
#> attr(,"offenders")
#> [1] "h1" "h2" "h3"
```
