# Look up the labels of members

Returns one display name per code. A code without a label of the chosen
variant is returned unchanged, so the result is always usable as an axis
or legend text. `NA` in `members` stands for the frame itself and
returns the frame's label, or its name when it has none.

## Usage

``` r
scale_label(x, members, frame, variant = NULL)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- members:

  Character vector of member codes at `frame`.

- frame:

  The frame the codes are at.

- variant:

  The label variant. `NULL` uses the scale's default, see
  [`attach_labels_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_labels_scale.md).

## Value

A character vector as long as `members`.

## See also

[`attach_labels_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_labels_scale.md),
[`scale_labels()`](https://optimal2050.github.io/nestedscales/r/reference/scale_labels.md)

## Examples

``` r
s <- attach_labels_scale(
  scale_example(),
  data.frame(frame = "sector", member = c("P", "S", NA),
             label = c("Primary", "Secondary", "Sector"))
)
scale_label(s, c("S", "P", "T"), frame = "sector")
#> [1] "Secondary" "Primary"   "T"        
scale_label(s, NA, frame = "sector")
#> [1] "Sector"
scale_label(s, c("G1", "G2"), frame = "class")   # no labels: the codes
#> [1] "G1" "G2"
```
