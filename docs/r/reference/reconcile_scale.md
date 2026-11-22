# Check fine data against an independent parent total

**\[experimental\]** This feature may change or be removed in a later
version.

Aggregates `data` from `source` to `target` and compares the result with
`totals`, the parent figure from another source. Reports the gap by
default; can also close it.

## Usage

``` r
reconcile_scale(
  data,
  x,
  source,
  target,
  totals,
  key = NULL,
  values = NULL,
  rule = "sum",
  weight = NULL,
  balance = c("none", "residual", "proportional"),
  tolerance = 1e-09
)
```

## Arguments

- data:

  The fine data, keyed at `source`.

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- source, target:

  Frame names: where the data is, and the coarser frame whose totals it
  is checked against.

- totals:

  The independent parent figures: a table keyed at `target` carrying the
  same value columns as `data`, plus any identifier columns (which are
  matched, so a per-year total works).

- key:

  Column of `data` holding the codes at `source`; defaults as in
  [`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md).

- values:

  Value columns to check. Default: the numeric columns common to `data`
  and `totals`.

- rule:

  How the value aggregates. `"sum"` (default) is the question "does it
  add up"; an intensive quantity reconciles as `"weighted_mean"`
  instead.

- weight:

  Weight column for `rule = "weighted_mean"`.

- balance:

  What to do about the gap:

  - `"none"` (default) – report it and change nothing.

  - `"residual"` – return the data with each group's gap written onto
    its declared residual member at `source`. Needs exactly one residual
    per affected group, and `rule = "sum"`.

  - `"proportional"` – return the data scaled by `target / aggregated`
    within each group, so every group hits its total.

- tolerance:

  Relative size below which a gap counts as rounding; sets the `ok`
  column, and gaps within it are left alone when balancing.

## Value

With `balance = "none"`, a long gap table: the `target` column, any
identifiers, `value` (which column), `aggregated`, `target`, `gap`
(`target - aggregated`), `rel_gap` and `ok`. With a balancing method,
the adjusted data keyed as the input was, carrying that same table as
its `"reconciliation"` attribute.

## Examples

``` r
lf <- data.frame(
  country = c("DE", "DE", "DE"),
  item = c("DE1", "DE2", "DE_XR"),
  pop = c(40, 30, 0), stringsAsFactors = FALSE
)
s <- scale_from_leaftable(lf,
  frames = c("country", "item"), leaf = "item",
  weights = "pop", name = "geo",
  residuals = list(item = "DE_XR")
)
fine <- data.frame(item = c("DE1", "DE2", "DE_XR"), gdp = c(400, 300, 0))
published <- data.frame(country = "DE", gdp = 750)

reconcile_scale(fine, s, source = "item", target = "country", published)
#>   country value aggregated target gap    rel_gap    ok
#> 1      DE   gdp        700    750  50 0.06666667 FALSE

reconcile_scale(fine, s,
  source = "item", target = "country", published,
  balance = "residual"
)
#>    item gdp
#> 1   DE1 400
#> 2   DE2 300
#> 3 DE_XR  50
```
