# Match labels to members, strictly

Resolves each label to a `(frame, member)` member in two stages,
stopping at the first that hits: an **exact** member name
(case-insensitive), then an **alias** (case-insensitive). A label that
hits several members – the same name at two frames, or an alias shared
by two members – is reported as `"ambiguous"` with the candidates,
unless `frame=` narrows the search to one frame. A label that hits
nothing is `"none"`. Nothing is guessed: no fuzzy matching, no substring
matching.

## Usage

``` r
scale_match(x, labels, frame = NULL, source = NULL)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- labels:

  Character vector of labels to resolve.

- frame:

  Restrict matching to one frame; `NULL` searches all frames and the
  leaf column.

- source:

  Restrict the alias stage to one source (or several).

## Value

A `data.frame` with one row per label: `label`, `frame`, `member`,
`method` (`"exact"`, `"alias"`, `"ambiguous"`, `"none"`) and
`candidates` (the `frame/member` pairs of an ambiguous hit, joined by
`"; "`, else `NA`).

## Examples

``` r
s <- scale_example()
scale_match(s, c("P", "G1", "u1", "nope"))   # G1 is a class AND a group
#>   label  frame member    method         candidates
#> 1     P sector      P     exact               <NA>
#> 2    G1   <NA>   <NA> ambiguous class/G1; group/G1
#> 3    u1   item     U1     exact               <NA>
#> 4  nope   <NA>   <NA>      none               <NA>
scale_match(s, "G1", frame = "group")
#>   label frame member method candidates
#> 1    G1 group     G1  exact       <NA>
```
