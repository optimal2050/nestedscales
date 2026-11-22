# Clear the rule registry

Mainly useful in tests.

## Usage

``` r
clear_scale_rules(name = NULL, scope = NULL)
```

## Arguments

- name:

  Optional character vector of parameter names to remove. `NULL`
  (default) clears everything in `scope`.

- scope:

  Optional dimension namespace.

## Value

Invisibly `NULL`.

## Examples

``` r
register_scale_rule("tmp_param", "sum")
clear_scale_rules("tmp_param")
```
