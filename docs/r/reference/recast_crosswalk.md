# Recast values through a given crosswalk

The engine behind
[`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md),
for a crosswalk built elsewhere: by a dimension package whose conversion
cannot be read off one scale's leaftable, such as timescales mapping one
calendar onto another through a datetime grid. The crosswalk says how
much of each source code falls in each target code; the rules then
aggregate exactly as in
[`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md),
on any supported backend.

## Usage

``` r
recast_crosswalk(
  data,
  map,
  source,
  target,
  key = source,
  values = NULL,
  rule = NULL,
  ids = NULL,
  by = character(),
  targets = NULL,
  missing_sources = c("na", "ignore"),
  member = "member",
  collect = NULL
)
```

## Arguments

- data:

  The data, in any supported backend, with a code column and one or more
  numeric value columns.

- map:

  The crosswalk, a `data.frame`.

- source, target:

  Names of the source and target code columns of `map`.

- key:

  Name of the code column of `data`. Defaults to `source`.

- values:

  Value columns. Default: every numeric column that is neither `key` nor
  in `ids`.

- rule:

  One of
  [`SCALE_RULES`](https://optimal2050.github.io/nestedscales/r/reference/SCALE_RULES.md)
  other than the share rules, for every value column, or a named vector
  with one entry per column. `NULL` looks each column up with
  [`get_scale_rule()`](https://optimal2050.github.io/nestedscales/r/reference/get_scale_rule.md).

- ids:

  Identifier columns, preserved as groups. Default: every column that is
  neither `key` nor a value column. Other columns are dropped.

- by:

  Columns of `map` matched against the identically named identifier
  columns of `data`, for a crosswalk that differs between identifier
  values (a calendar crosswalk per year, say).

- targets:

  Optional full target vocabulary. A materialised result is completed to
  every target per identifier combination, in this order, with `NA`
  where nothing landed; an `NA` entry adds an explicit `NA` row.

- missing_sources:

  `"na"` (default) or `"ignore"`; see
  [`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md).

- member:

  The word for a target code in error messages.

- collect:

  For lazy inputs: materialise (`TRUE`) or return the query.

## Value

The recast data in its own class, with columns `c(to, ids, values)`.
Lazy in, lazy out.

## Details

The crosswalk is a data frame with one row per (source, target) pair:

- the source and target codes, in the columns named by `source` and
  `target`;

- `n_from`, the number of leaves (grid points) in the source code, and
  `n_overlap`, the number of them that fall in the target;

- optionally `w`, the weight of the pair for `"weighted_mean"` – by
  default `n_overlap`;

- optionally `w_from`, the source's total weight. With it, `"sum"`
  splits a source across its targets by `w / w_from`; without it, by
  `n_overlap / n_from`, an equal split over leaves;

- any columns named in `by`.

A target whose sources are only partly present in the data, per
identifier combination, comes back `NA` unless
`missing_sources = "ignore"`.

## Examples

``` r
# Two months onto one quarter, with the months' day counts as leaves
map <- data.frame(
  month = c("m01", "m02"), quarter = "Q1",
  n_from = c(31, 28), n_overlap = c(31, 28)
)
d <- data.frame(
  month = c("m01", "m02"), energy = c(310, 280),
  price = c(10, 20)
)
recast_crosswalk(d, map,
  source = "month", target = "quarter",
  rule = c(energy = "sum", price = "weighted_mean")
)
#>   quarter energy    price
#> 1      Q1    590 14.74576
```
