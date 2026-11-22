# Do two frames nest?

Tests whether every code at the finer frame falls entirely within a
single code at the coarser frame. Real hierarchies often fail this: a
spatial code can straddle two parents, and a reporting classification
can assign one detailed class to several aggregates.

## Usage

``` r
scale_nests(x, parent, child)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- parent, child:

  Frame names.

## Value

`TRUE` or `FALSE`. When `FALSE`, the offending child codes are attached
as the `"offenders"` attribute.

## Details

Nesting is *not* required by
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
– conversion routes through the leaf layer and works either way. This
function is a diagnostic.

## Examples

``` r
s <- scale_example()
scale_nests(s, "class", "group") # FALSE - they cross-cut
#> [1] FALSE
#> attr(,"offenders")
#> [1] "GB"
```
