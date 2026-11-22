# Recast values from one resolution to another

The central conversion verb: takes a table keyed by member code at frame
`source` and returns one keyed at `target` – a frame name of the same
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md),
or ANOTHER NestedScale (whose leaf layer is the target, matched on
shared leaf codes). Handles both aggregation (fine to coarse) and
disaggregation (coarse to fine) with one rule per value column; frames
that cross-cut work too, because the route always goes through the leaf
layer. A crosswalk registered with
[`register_scale_map()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_map.md)
short-circuits the derivation.

## Usage

``` r
recast_scale(
  data,
  x,
  source = NULL,
  target,
  key = NULL,
  values = NULL,
  rule = NULL,
  weight = NULL,
  na_action = c("drop", "error", "keep"),
  parent = NULL,
  collect = NULL,
  diagnostics = c("auto", "on", "off"),
  missing_sources = c("na", "ignore"),
  batch = NULL,
  batch_by = NULL,
  ...
)
```

## Arguments

- data:

  The data to recast, in any supported backend, with a column named by
  `key` plus one or more numeric value columns; other columns are
  preserved as identifiers.

- x:

  The
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  the codes in `data` belong to.

- source:

  Frame name the codes belong to. `NULL` (default) is inferred: `key`
  when it is a frame name, else the single frame name appearing among
  the data's columns.

- target:

  Target frame name of `x`, or another (named)
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  – then the target is that object's leaf layer, matched on shared leaf
  codes.

- key:

  Name of the code column in `data`. Defaults to `source` when that
  column exists, otherwise the name of the scale's leaf column.

- values:

  Character vector of value columns to convert. Default: all numeric
  columns other than the key and the scale's frame columns. Numeric
  identifiers (e.g. `year`) must be excluded explicitly.

- rule:

  One of
  [`SCALE_RULES`](https://optimal2050.github.io/nestedscales/r/reference/SCALE_RULES.md)
  applied to every value column, or a named vector with one entry per
  column; `NULL` (default) looks each column up with
  [`get_scale_rule()`](https://optimal2050.github.io/nestedscales/r/reference/get_scale_rule.md).
  A column with neither an explicit rule nor a registry entry is an
  ERROR – there is deliberately no fallback (a silently guessed rule is
  a silent unit error).

- weight:

  Weight column used by `sum` (splitting) and `weighted_mean`; scalar or
  named per column. `NULL` uses each column's registered weight, falling
  back to the object's default weight; when the object declares no
  weights at all, leaves weigh 1 (an equal split, warned about when it
  is material).

- na_action:

  What to do with leaves that have no code at `source` or `target`:
  `"drop"` (default, with a warning – the affected source share is
  genuinely lost), `"error"`, or `"keep"` (retain an explicit `NA` row
  so totals conserve).

- parent:

  `rule = "share"` only: the frame defining the groups the shares are
  taken within. `NULL` (default) uses `target` when it differs from
  `source`, else the frame immediately above `source`.

- collect:

  For lazy inputs: materialise the result (`TRUE`) or return the
  uncollected query (default).

- diagnostics:

  Whether to run the checks that need a scan of the data: unknown source
  codes, dropped shares, and source members missing from the data.
  `"auto"` (default) runs them on eager inputs and skips them on
  arrow/dtplyr, where a scan would defeat the point of returning a
  query; `"on"` and `"off"` force the choice. Errors that do not depend
  on the data – unknown frames, reserved column names, a missing rule –
  are raised regardless.

- missing_sources:

  What to do when a target member's sources are only partially present
  in the data. `"na"` (default) makes the result `NA` – a partial answer
  is not an answer. `"ignore"` aggregates whatever is there, which is
  faster but silently turns incomplete data into a plausible number, so
  it is opt-in.

- batch, batch_by:

  Process the job in chunks of at most `batch` distinct values of the
  identifier column `batch_by` (default: the first identifier column),
  binding the pieces. Chunking by an identifier partitions the
  aggregation groups exactly, so the numbers are unchanged; any other
  column is refused. Applies only when materialising, and turns off
  per-chunk diagnostics, which would otherwise report sources as missing
  merely because they fall in another chunk.

- ...:

  Passed to
  [`scale_map()`](https://optimal2050.github.io/nestedscales/r/reference/scale_map.md)
  (e.g. `year` for a calendar).

## Value

The recast table in the input's class, with columns
`c(to, identifiers, values)`.

## Details

Columns of the data that are neither the key nor a value column are
treated as identifiers (panel columns – a year, a technology) and
preserved as grouping columns, so panel data recasts correctly in one
call. This is what makes mixed pipelines across two dimensions work: a
recast in one dimension carries the other dimension's key through
untouched. Columns named like the scale's own frames are treated as
member attributes and dropped.

`"sum"` splits each source value across its member's leaves
proportionally to the weight before summing up, so totals are conserved.
`"weighted_mean"` weights by the leaf weights; `"mean"` is the plain
leaf-count mean – the two differ exactly when leaf weights differ.
`"copy"` requires a constant value per target member; `"sd"` is
aggregation-only.

`"share"` inverts the output contract: the result stays keyed at
`source`, and each value becomes that member's share of the total over
its parent group. `source` must nest within the parent. It cannot be
combined with other rules in one call, and `weight=` is ignored – the
observed values themselves are the weights.

## Backends

The data may be a `data.frame`, tibble, `data.table`, `dtplyr` lazy
table, or an arrow Dataset/Table/query. The result comes back in the
input's class; lazy inputs return the uncollected query unless
`collect = TRUE`. Lazy results contain the observed target members only
– the full-vocabulary completion (and its `NA` rows) applies when the
result is materialised.

## Examples

``` r
s <- scale_example()

# Extensive quantity, fine -> coarse: totals are preserved
d <- data.frame(
  item = c("U1", "U2", "U3", "U4", "U5", "U6"),
  capacity = c(1, 2, 3, 4, 5, 6)
)
recast_scale(d, s, source = "item", target = "sector", rule = "sum")
#>   sector capacity
#> 1      P       10
#> 2      S       11

# Coarse -> fine: split proportionally to size
y <- data.frame(sector = c("P", "S"), capacity = c(10, 20))
recast_scale(y, s,
  source = "sector", target = "class",
  rule = "sum", weight = "size"
)
#>   class capacity
#> 1    G1        3
#> 2    G2        7
#> 3    S1       20

# Share within parent: result stays at the leaves, sums to 1 per sector
recast_scale(
  d, s,
  source = "item", target = "sector",
  rule = "share",
  na_action = "keep"
)
#>   item  capacity
#> 1   U1 0.1000000
#> 2   U2 0.2000000
#> 3   U3 0.3000000
#> 4   U4 0.4000000
#> 5   U5 0.4545455
#> 6   U6 0.5454545
#> 7  OTH        NA
```
