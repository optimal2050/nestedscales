# Build a NestedScale from a flat table of leaves

The general constructor. Takes a wide `data.frame` with one row per leaf
(the finest member) and one column per frame, and returns a
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

## Usage

``` r
scale_from_leaftable(
  leaftable,
  frames,
  leaf = NULL,
  weights = NULL,
  default_weight = NULL,
  members = NULL,
  name = "",
  desc = "",
  attributes = NULL,
  aliases = NULL,
  labels = NULL,
  ...
)
```

## Arguments

- leaftable:

  `data.frame` with one row per leaf, one column per name in `frames`,
  and optionally numeric weight columns.

- frames:

  Ordered character vector of frame names, **coarsest first**. Each must
  be a column of `leaftable`.

- leaf:

  Name of the leaf column: the column that identifies the leaves, one
  unique code per row. Defaults to a column called `"leaf"` if present,
  otherwise to the finest frame (the last entry of `frames`).

- weights:

  Character vector naming the weight columns. Defaults to all numeric
  columns that are neither frames nor reserved names.

- default_weight:

  The weight used when a caller does not name one. Defaults to the first
  entry of `weights`.

- members:

  Optional named list giving the ordered code vocabulary per frame.
  Derived from `leaftable` when `NULL` (first-appearance order).

- name, desc:

  Short name and description.

- attributes:

  Optional table of per-member physical attributes keyed by
  `(frame, member)`; see
  [`attach_attributes_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_attributes_scale.md)
  for the columns.

- aliases:

  Optional table of alternative labels keyed by `(frame, member)`; see
  [`attach_aliases_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_aliases_scale.md)
  for the columns.

- labels:

  Optional table of display names keyed by `(frame, member, variant)`;
  see
  [`attach_labels_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_labels_scale.md)
  for the columns.

- ...:

  Further named entries merged into `meta` (e.g. `source`).

## Value

A
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

## Details

Blank strings (`""`) in frame columns are normalised to `NA`, meaning
"this leaf has no code at this frame" – partial coverage is normal in
real classification tables.

## Examples

``` r
df <- data.frame(
  section = c("A", "A", "A", "B"),
  group   = c("A1", "A1", "A2", "B1"),
  item    = c("A11", "A12", "A21", "B11"),
  gva     = c(100, 200, 300, 400)
)
scale_from_leaftable(df, frames = c("section", "group", "item"))
#> NestedScale: <unnamed>
#> Frames (3, coarsest first):
#>   - section (2)
#>     - group (3)
#>       - item (4)
#> Leaves: 4
#> Weights: gva (default: gva)
```
