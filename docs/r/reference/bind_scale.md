# Bind a table to a scale

**\[experimental\]** This feature may change or be removed in a later
version.

Records, on the code columns themselves, which scale and which frame
their codes are on. A bound column is a
[`scale_member`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_member.md)
vector: it prints and behaves as a character vector, and keeps the link
through row subsetting, `mutate()`, grouping, joins and row binding. The
verbs
([`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md),
[`join_scale()`](https://optimal2050.github.io/nestedscales/r/reference/join_scale.md),
the leaf routes) then take the source frame from the link, stop when the
data is bound to a different scale, and bind their result.

## Usage

``` r
bind_scale(data, x, cols = NULL)

unbind_scale(data, cols = NULL)

scale_link(data)
```

## Arguments

- data:

  A `data.frame`, tibble or `data.table`; for `scale_link()` also a
  `scale_dataset` from
  [`open_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/open_scale_dataset.md).

- x:

  The
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  the codes belong to.

- cols:

  Which columns to bind. `NULL` (default) binds every column named after
  a frame of `x` (or after its leaf column). Otherwise a character
  vector of frame names, named by column where the column is called
  something else: `c(origin = "sector")`. For `unbind_scale()`, the
  columns to unbind; `NULL` for all bound columns.

## Value

`bind_scale()` and `unbind_scale()` return `data`; `scale_link()` a
`data.frame` with one row per bound column: `column`, `scale`, `frame`,
`id`.

## Details

The link is experimental and may change or be removed. It is an R
construct: converting a bound column to a factor or to a plain character
vector drops it, and other languages reading the same data do not see
it. Data that is not bound is matched to a scale by its codes alone.

Every code is checked against the scale when binding; a code that is not
a member is an error. `scale_link()` reports what a table is bound to
and `unbind_scale()` returns the columns to plain character.

A lazy table (arrow, dtplyr) cannot carry the link: collect it first, or
keep the link on disk with
[`write_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale_dataset.md).

## See also

[`scale_id()`](https://optimal2050.github.io/nestedscales/r/reference/scale_id.md),
[`as_scale_member()`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_member.md)

## Examples

``` r
s <- scale_example()
d <- data.frame(class = c("G1", "G2", "S1"), v = 1:3)
b <- bind_scale(d, s)
scale_link(b)
#>   column   scale frame               id
#> 1  class example class example@c24a3e23

# the source frame comes from the link, and the result is bound
out <- recast_scale(b, s, target = "sector", rule = "sum")
scale_link(out)
#>   column   scale  frame               id
#> 1 sector example sector example@c24a3e23

# data bound to one scale is refused by another
try(recast_scale(b, scale_example2(), target = "sector", rule = "sum"))
#> Error : cannot infer the source frame from the data's columns (found: none); pass `source=`

unbind_scale(b)$class
#> [1] "G1" "G2" "S1"
```
