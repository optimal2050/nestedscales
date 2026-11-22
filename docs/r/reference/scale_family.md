# Immediate parent-child table between two frames

Immediate parent-child table between two frames

## Usage

``` r
scale_family(x, parent = NULL, child = NULL)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- parent, child:

  Frame names. Defaults to every adjacent pair in `x@frames`.

## Value

A `data.frame` with columns `parent_frame`, `parent`, `child_frame`,
`child`. Leaves unassigned at either frame are omitted.

## Examples

``` r
s <- scale_example()
scale_family(s, "group", "item")
#>   parent_frame parent child_frame child
#> 1        group     G1        item    U1
#> 2        group     G1        item    U2
#> 3        group     GB        item    U3
#> 4        group     GB        item    U4
#> 5        group     GB        item    U5
#> 6        group     GC        item    U6
```
