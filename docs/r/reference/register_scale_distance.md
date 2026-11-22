# Register a distance

**\[experimental\]** This feature may change or be removed in a later
version.

The built-ins cover level and shape; anything else – dynamic time
warping, a domain-specific dissimilarity, a precomputed matrix – is
registered here and then usable by name everywhere in the package.

## Usage

``` r
register_scale_distance(name, fn)

get_scale_distance(name)

list_scale_distances()

clear_scale_distances(name = NULL)
```

## Arguments

- name:

  Distances to remove; `NULL` clears every registered one. Built-ins
  cannot be removed.

- fn:

  A function of the member-by-feature matrix returning a
  [stats::dist](https://rdrr.io/r/stats/dist.html) object (or a square
  matrix) over its rows.

## Value

Invisibly, `name`.

## Examples

``` r
register_scale_distance("first_diff", function(m) {
  stats::dist(t(apply(m, 1, diff)))
})
"first_diff" %in% list_scale_distances()
#> [1] TRUE
clear_scale_distances("first_diff")
```
