# Clear the registered crosswalks

Mainly useful in tests.

## Usage

``` r
clear_scale_maps(name = NULL)
```

## Arguments

- name:

  Registry keys to remove (as listed by
  [`list_scale_maps()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_map.md));
  `NULL` (default) clears every registered crosswalk.

## Value

Invisibly `NULL`.

## Examples

``` r
clear_scale_maps()
```
