# NestedScale (S7 class)

A nested discrete partition: a flat table of leaves plus the ordered
hierarchy of frames that groups them. The dimension is not named – time
and space are the subclasses `Calendar` (timescales) and `Geoscale`
(geoscales); anything else (industries, income brackets, temperature
regimes, technology vintages) is declared directly.

## Usage

``` r
NestedScale(
  leaftable,
  frames,
  members,
  leaf = "leaf",
  meta = list(),
  attributes = NULL,
  aliases = NULL,
  labels = NULL
)
```

## Arguments

- leaftable:

  `data.frame` with a unique leaf column, one column per frame in
  `frames`, and zero or more numeric weight columns.

- frames:

  Ordered character vector of frame names (coarsest first); each must
  appear as a column of `leaftable`.

- members:

  Named list; `members[[f]]` is the full ordered set of codes present at
  frame `f`. Must equal the non-`NA` values of `leaftable[[f]]` as a
  set.

- leaf:

  Name of the leaf column (a single string, default `"leaf"`).

- meta:

  Named list of attributes (`name`, `desc`, `weights`, `default_weight`,
  `residuals` (see
  [`scale_residuals()`](https://optimal2050.github.io/nestedscales/r/reference/scale_residuals.md)),
  `default_label`, `source`, sample bookkeeping).

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

## Value

A `NestedScale` object.

## Details

Construct with
[`scale_from_leaftable()`](https://optimal2050.github.io/nestedscales/r/reference/scale_from_leaftable.md).

## See also

[`scale_from_leaftable()`](https://optimal2050.github.io/nestedscales/r/reference/scale_from_leaftable.md),
[`scale_frames()`](https://optimal2050.github.io/nestedscales/r/reference/scale_frames.md),
[`scale_members()`](https://optimal2050.github.io/nestedscales/r/reference/scale_members.md)

## Examples

``` r
scale_example()
#> NestedScale: example
#> Description: Synthetic example: reused code, non-nesting frame pair, and an unassigned leaf 
#> Frames (4, coarsest first):
#>   - sector (2)  [1 member unassigned]
#>     - class (3)  [1 member unassigned]
#>       - group (3)  [1 member unassigned]
#>         - item (7)
#> Leaves: 7
#> Weights: size, count (default: size)
```
