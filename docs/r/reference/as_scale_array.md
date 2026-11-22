# Data on scales as a dense array

**\[experimental\]** This feature may change or be removed in a later
version.

Reshapes a long table into an array whose dimensions are the scale's
axes, in the order the product declares them, with the members as
`dimnames`.

## Usage

``` r
as_scale_array(data, x, value = NULL, frames = NULL, fill = NA, limit = 1e+07)

as_scale_table(a, x, value = "value", frames = NULL, drop_na = TRUE)
```

## Arguments

- data:

  A long table with one column per axis key plus the value column. Lazy
  inputs are materialised – an array is a dense in-memory object by
  definition.

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  or
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

- value:

  Name of the value column. Defaults to the single numeric column that
  is not a key.

- frames:

  Optional named list giving the frame each axis is keyed at; defaults
  to each axis's leaf frame.

- fill:

  Value for cells the data does not cover.

- limit:

  Refuse to allocate more than this many cells.

- a:

  An array produced by `as_scale_array()` (or shaped like one).

- drop_na:

  Omit cells the array does not cover, rather than emitting them as rows
  with `NA` values.

## Value

An array with one dimension per axis.

`as_scale_table()` returns a `data.frame`: one column per axis key, plus
the value column.

## Examples

``` r
p <- scale_product(a = scale_example(), b = scale_example2())
d <- merge(
  data.frame(item = c("U1", "U2")),
  data.frame(period = c("p1", "p2"))
)
d$v <- 1:4
as_scale_array(d, p, value = "v")
#>      b
#> a     p1 p2 p3 p4
#>   U1   1  3 NA NA
#>   U2   2  4 NA NA
#>   U3  NA NA NA NA
#>   U4  NA NA NA NA
#>   U5  NA NA NA NA
#>   U6  NA NA NA NA
#>   OTH NA NA NA NA
as_scale_table(as_scale_array(d, p, value = "v"), p, value = "v")
#>   item period v
#> 1   U1     p1 1
#> 2   U2     p1 2
#> 3   U1     p2 3
#> 4   U2     p2 4
```
