# Read attributes, resolved along the hierarchy

**\[experimental\]** This feature may change or be removed in a later
version.

With `frame = NULL`, returns the stored attribute table (filtered by
`attribute` and `source`). With a `frame`, returns one row per member of
that frame per attribute, **resolved**: a member's own value when it has
one, otherwise the value of its nearest ancestor that has one, walking
coarser frames one at a time. The row reports where the value came from
in `origin_frame`/`origin_member`; a member with no value anywhere gets
an `NA` row.

## Usage

``` r
scale_attributes(
  x,
  attribute = NULL,
  frame = NULL,
  source = NULL,
  inherit = TRUE
)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- attribute:

  Character vector of attribute names; `NULL` for all.

- frame:

  Frame whose members to resolve for; `NULL` returns the stored table
  unresolved.

- source:

  Restrict to one source (or several). `NULL` uses whatever is stored
  and errors on a conflict.

- inherit:

  Walk to coarser frames for members without a value of their own
  (default `TRUE`). `FALSE` reports stored values only.

## Value

A `data.frame` with the attribute columns (`frame`, `member`,
`attribute`, `kind`, `value`, `lower`, `upper`, `unit_of_measure`,
`source`, `note`), plus `origin_frame` and `origin_member` when `frame`
is given.

## Details

Two situations are errors rather than guesses:

- the walk reaches a frame where the member has **several** ancestors
  (the frames cross-cut) and at least one of them holds the attribute –
  "inheritance is ambiguous";

- several `source`s publish the attribute for the same member and
  `source` is `NULL` – pass `source=` to choose.

## Examples

``` r
s <- attach_attributes_scale(
  scale_example(),
  data.frame(frame = c("sector", "class"), member = c("P", "S1"),
             attribute = "density", value = c(10, 5),
             unit_of_measure = "t/m3"),
  source = "survey", kind = "property"
)
scale_attributes(s)                           # stored rows
#>    frame member attribute     kind value lower upper unit_of_measure source
#> 1 sector      P   density property    10    NA    NA            t/m3 survey
#> 2  class     S1   density property     5    NA    NA            t/m3 survey
#>   note
#> 1 <NA>
#> 2 <NA>
scale_attributes(s, "density", frame = "item") # resolved per leaf
#>   frame member attribute     kind value lower upper unit_of_measure source note
#> 1  item     U1   density property    10    NA    NA            t/m3 survey <NA>
#> 2  item     U2   density property    10    NA    NA            t/m3 survey <NA>
#> 3  item     U3   density property    10    NA    NA            t/m3 survey <NA>
#> 4  item     U4   density property    10    NA    NA            t/m3 survey <NA>
#> 5  item     U5   density property     5    NA    NA            t/m3 survey <NA>
#> 6  item     U6   density property     5    NA    NA            t/m3 survey <NA>
#> 7  item    OTH   density     <NA>    NA    NA    NA            <NA>   <NA> <NA>
#>   origin_frame origin_member
#> 1       sector             P
#> 2       sector             P
#> 3       sector             P
#> 4       sector             P
#> 5        class            S1
#> 6        class            S1
#> 7         <NA>          <NA>
```
