# Read the alias table

Read the alias table

## Usage

``` r
scale_aliases(x, frame = NULL, source = NULL)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- frame:

  Restrict to one frame; `NULL` for all.

- source:

  Restrict to one source (or several); `NULL` for all.

## Value

A `data.frame` with columns `frame`, `member`, `alias`, `source`.

## Examples

``` r
s <- attach_aliases_scale(
  scale_example(),
  data.frame(frame = "sector", member = "P", alias = "primary"),
  source = "labels"
)
scale_aliases(s)
#>    frame member   alias source
#> 1 sector      P primary labels
scale_aliases(s, frame = "class")
#> [1] frame  member alias  source
#> <0 rows> (or 0-length row.names)
```
