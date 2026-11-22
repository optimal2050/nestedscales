# Navigate a NestedScale's hierarchy

Codes related to `member` at another frame, found through the leaves.
`scale_children()`/`scale_parents()` step one frame down/up by default;
`scale_descendants()`/`scale_ancestors()` report every finer/coarser
frame as a frame-tagged table.

## Usage

``` r
scale_children(x, frame, member, target = NULL)

scale_parents(x, frame, member, target = NULL)

scale_descendants(x, frame, member, target = NULL)

scale_ancestors(x, frame, member, target = NULL)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- frame:

  The frame `member` belongs to.

- member:

  Character vector of codes.

- target:

  Target frame. `NULL` uses the adjacent frame (children/parents) or
  every finer/coarser frame (descendants/ancestors).

## Value

A character vector (children/parents) or a `data.frame` with columns
`frame` and `member` (descendants/ancestors).

## Examples

``` r
s <- scale_example()
scale_children(s, "sector", "P")
#> [1] "G1" "G2"
scale_parents(s, "item", "U5")
#> [1] "GB"
scale_descendants(s, "sector", "P")
#>   frame member
#> 1 class     G1
#> 2 class     G2
#> 3 group     G1
#> 4 group     GB
#> 5  item     U1
#> 6  item     U2
#> 7  item     U3
#> 8  item     U4
scale_ancestors(s, "item", "U5")
#>    frame member
#> 1 sector      S
#> 2  class     S1
#> 3  group     GB
```
