# Register / look up a direct crosswalk

A registered map short-circuits the leaf-layer derivation in
[`scale_map()`](https://optimal2050.github.io/nestedscales/r/reference/scale_map.md)
or
[`scale_map_between()`](https://optimal2050.github.io/nestedscales/r/reference/scale_map_between.md)
(and thereby
[`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md))
for one pair of resolutions – for cases where the exact correspondence
is known (hand-audited crosswalks, official concordance tables).

## Usage

``` r
register_scale_map(x, source, target, map)

register_scale_map_between(source, target, map)

get_scale_map(x, source, target)

get_scale_map_between(source, target)

list_scale_maps()
```

## Arguments

- x:

  The
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  the frames belong to, or its name.

- source, target:

  For the within-scale functions, frame names of `x`. For the `_between`
  functions, two
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  objects or their names.

- map:

  A `data.frame` shaped like a
  [`scale_map()`](https://optimal2050.github.io/nestedscales/r/reference/scale_map.md)
  result: the two label columns named after the frames (or scales), plus
  `n_from`, `n_overlap`, `w` and `w_from`. `NULL` removes a previously
  registered map.

## Value

Invisibly, the registry key. The `get_` functions return the registered
map (or `NULL`); `list_scale_maps()` a `data.frame` of registry keys.

## Details

`register_scale_map()` and `get_scale_map()` handle a pair of frames of
one scale; the map is scoped to that scale, so the same frame pair in
two different scales does not collide. `register_scale_map_between()`
and `get_scale_map_between()` handle a pair of scales.

## Examples

``` r
s <- scale_example()
fake <- data.frame(
  class = "G1", group = "GC", n_from = 1L,
  n_overlap = 1L, w = 1, w_from = 1
)
register_scale_map(s, "class", "group", fake)
list_scale_maps()
#>                    key
#> 1 example:class->group
get_scale_map(s, "class", "group")
#>   class group n_from n_overlap w w_from
#> 1    G1    GC      1         1 1      1
register_scale_map(s, "class", "group", NULL) # remove
clear_scale_maps()
```
