# Attach labels to a scale

Adds display names to the object's label table. A label belongs to a
member (`frame`, `member`) and to a `variant` – a free name such as
`"name"`, `"short"` or a language code – so a member may carry several.
The table is sparse: frames and members without a row are shown by their
code. A row with `member = NA` labels the frame itself.

## Usage

``` r
attach_labels_scale(
  x,
  labels,
  variant = NULL,
  default = NULL,
  overwrite = FALSE
)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- labels:

  A `data.frame` with columns `frame`, `member`, `label` and, unless
  `variant` is given, optionally `variant`.

- variant:

  Single string filled into the `variant` column when `labels` has none.
  Defaults to `"label"`.

- default:

  Single string naming the variant used when a lookup names none. `NULL`
  keeps the current default (initially the first variant attached).

- overwrite:

  Replace the label of a (`frame`, `member`, `variant`) already present.
  `FALSE` (default) makes that an error.

## Value

The scale with the rows added.

## Details

Labels are for display. Alternative spellings to be *matched* belong in
the alias table, see
[`attach_aliases_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_aliases_scale.md).

## See also

[`scale_labels()`](https://optimal2050.github.io/nestedscales/r/reference/scale_labels.md),
[`scale_label()`](https://optimal2050.github.io/nestedscales/r/reference/scale_label.md)

## Examples

``` r
s <- attach_labels_scale(
  scale_example(),
  data.frame(frame = "sector", member = c("P", "S", NA),
             label = c("Primary", "Secondary", "Sector"))
)
scale_labels(s)
#>    frame member variant     label
#> 1 sector      P   label   Primary
#> 2 sector      S   label Secondary
#> 3 sector   <NA>   label    Sector
scale_label(s, c("P", "S", "T"), frame = "sector")
#> [1] "Primary"   "Secondary" "T"        
```
