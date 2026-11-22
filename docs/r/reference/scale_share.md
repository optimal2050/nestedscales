# Weight shares within a frame

Normalised weights, either of the whole object or within each parent
group.

## Usage

``` r
scale_share(x, frame, weight = NULL, within = NULL)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- frame:

  Frame to report shares for.

- weight:

  Weight column. `NULL` uses the default.

- within:

  Optional coarser frame to normalise within. `NULL` normalises over the
  whole object.

## Value

A `data.frame` with a code column named `frame`, the weight, and
`share`. When `within` is given, a column of that name carries the
parent code.

## Examples

``` r
s <- scale_example()
scale_share(s, "class", weight = "size")
#>   class size     share
#> 1    G1  300 0.1428571
#> 2    G2  700 0.3333333
#> 3    S1 1100 0.5238095
scale_share(s, "class", weight = "size", within = "sector")
#>   class sector size share
#> 1    G1      P  300   0.3
#> 2    G2      P  700   0.7
#> 3    S1      S 1100   1.0
```
