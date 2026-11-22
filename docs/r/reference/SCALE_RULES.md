# Supported aggregation rules

Each rule defines behaviour in **both** directions. Direction is taken
from the frame ranks, so aggregation and disaggregation are one
operation:

## Usage

``` r
SCALE_RULES
```

## Format

A character vector of length 7.

## Value

A character vector of the seven rule names accepted by the `rule`
argument of
[`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md)
and
[`register_scale_rule()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_rule.md).

## Details

- `sum`:

  Up: sum. Down: split proportionally to the weight. For extensive
  quantities (capacity, demand, area, population).

- `weighted_mean`:

  Up: weight-weighted mean. Down: copy unchanged. For intensive
  quantities (efficiency, price, capacity factor).

- `mean`:

  Up: unweighted mean. Down: copy unchanged.

- `copy`:

  Up: the common value, erroring if it is not constant. Down: copy
  unchanged. For scale-invariant scalars.

- `sd`:

  Up: standard deviation over the leaves (aggregation only; going down
  it degenerates to `NA` for single-leaf groups).

- `share`:

  Share within parent: each source member's value divided by the total
  over its parent group. Unlike every other rule the result stays keyed
  at the **source** frame – the recast target (or `parent=`) names the
  parent – so it cannot be mixed with other rules in one call (the two
  share rules mix freely, being one computation). For building
  distribution keys and normalised profiles; requires `from` to nest
  within the parent.

- `logshare`:

  The same computation as `share` – the values ARE shares – but figures
  draw it on a fixed log10 percent scale (0.01%..100%), where `share`
  gets a fixed linear 0..1 scale.

## Examples

``` r
SCALE_RULES
#> [1] "sum"           "weighted_mean" "mean"          "copy"         
#> [5] "sd"            "share"         "logshare"     
```
