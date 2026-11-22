# Attach aliases to a scale

Appends rows to the object's alias table: alternative labels by which a
member (`frame`, `member`) is known, tagged with the `source` the
spelling comes from (a palette, a model's commodity codes, a dataset).
The same alias may legitimately point at several members;
[`scale_match()`](https://optimal2050.github.io/nestedscales/r/reference/scale_match.md)
reports that as ambiguous unless the caller names the frame.

## Usage

``` r
attach_aliases_scale(x, aliases, source = NULL)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- aliases:

  A `data.frame` with columns `frame`, `member`, `alias` and, unless
  `source` is given, `source`.

- source:

  Optional single string filled into the `source` column.

## Value

The scale with the rows appended.

## Examples

``` r
s <- attach_aliases_scale(
  scale_example(),
  data.frame(frame = "sector", member = c("P", "S"),
             alias = c("primary", "secondary")),
  source = "labels"
)
scale_match(s, c("Primary", "G1", "nope"))
#>     label  frame member    method         candidates
#> 1 Primary sector      P     alias               <NA>
#> 2      G1   <NA>   <NA> ambiguous class/G1; group/G1
#> 3    nope   <NA>   <NA>      none               <NA>
```
