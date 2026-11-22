# Register how a parameter should be recast

Records the rule (and optionally the weight) to use for a named value
column, so callers of
[`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md)
need not repeat it. Downstream packages register their own parameter
maps at load time.

## Usage

``` r
register_scale_rule(param, rule, weight = NULL, scope = NULL)
```

## Arguments

- param:

  Name of the value column.

- rule:

  One of
  [`SCALE_RULES`](https://optimal2050.github.io/nestedscales/r/reference/SCALE_RULES.md).

- weight:

  Optional weight column name used by `sum` (down) and `weighted_mean`
  (up). `NULL` means the scale's default weight.

- scope:

  Optional dimension namespace (e.g. `"calendar"`, `"geoscale"`). `NULL`
  registers the rule for every dimension.

## Value

Invisibly, the registered entry.

## Examples

``` r
register_scale_rule("capacity", "sum")
register_scale_rule("eff", "weighted_mean", weight = "count")
get_scale_rule("eff")
#> $rule
#> [1] "weighted_mean"
#> 
#> $weight
#> [1] "count"
#> 
#> $scope
#> NULL
#> 
clear_scale_rules(c("capacity", "eff"))
```
