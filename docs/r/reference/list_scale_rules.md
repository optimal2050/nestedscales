# List registered rules

List registered rules

## Usage

``` r
list_scale_rules(scope = NULL)
```

## Arguments

- scope:

  Optional dimension namespace; `NULL` lists every entry.

## Value

A `data.frame` with columns `param`, `rule`, `weight` and `scope`.

## Examples

``` r
register_scale_rule("invcost", "weighted_mean", weight = "size")
list_scale_rules()
#>     param          rule weight scope
#> 1 invcost weighted_mean   size  <NA>
clear_scale_rules("invcost")
```
