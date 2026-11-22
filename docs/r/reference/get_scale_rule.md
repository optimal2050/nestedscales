# Look up a registered rule

A scoped lookup prefers the entry registered for that scope and falls
back to an unscoped one.

## Usage

``` r
get_scale_rule(param, scope = NULL)
```

## Arguments

- param:

  Name of the value column.

- scope:

  Optional dimension namespace.

## Value

A list with elements `rule`, `weight` and `scope`, or `NULL` if `param`
has not been registered.

## Examples

``` r
register_scale_rule("demand", "sum")
get_scale_rule("demand")
#> $rule
#> [1] "sum"
#> 
#> $weight
#> NULL
#> 
#> $scope
#> NULL
#> 
get_scale_rule("not_registered")
#> NULL
clear_scale_rules("demand")
```
