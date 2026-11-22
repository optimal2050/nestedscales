# Members of a NestedScale

The code vocabulary at one frame, in canonical order.

## Usage

``` r
scale_members(x, frame = NULL)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- frame:

  A single frame name; defaults to the finest frame (the leaves).

## Value

A character vector of member codes.

## Examples

``` r
s <- scale_example()
scale_members(s)
#> [1] "U1"  "U2"  "U3"  "U4"  "U5"  "U6"  "OTH"
scale_members(s, "group")
#> [1] "G1" "GB" "GC"
```
