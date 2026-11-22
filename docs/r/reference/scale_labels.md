# Read the label table

Read the label table

## Usage

``` r
scale_labels(x, frame = NULL, variant = NULL)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- frame:

  Restrict to one frame; `NULL` for all.

- variant:

  Restrict to one variant (or several); `NULL` for all.

## Value

A `data.frame` with columns `frame`, `member`, `variant`, `label`. A row
with `member = NA` is the label of the frame itself.

## See also

[`attach_labels_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_labels_scale.md),
[`scale_label()`](https://optimal2050.github.io/nestedscales/r/reference/scale_label.md)

## Examples

``` r
s <- attach_labels_scale(
  scale_example(),
  data.frame(frame = "sector", member = c("P", "S"),
             label = c("Primary", "Secondary"))
)
scale_labels(s)
#>    frame member variant     label
#> 1 sector      P   label   Primary
#> 2 sector      S   label Secondary
scale_labels(s, frame = "class")
#> [1] frame   member  variant label  
#> <0 rows> (or 0-length row.names)
```
