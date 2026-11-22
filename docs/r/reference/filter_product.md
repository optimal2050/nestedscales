# Subset a product componentwise

**\[experimental\]** This feature may change or be removed in a later
version.

Applies
[`filter_scale()`](https://optimal2050.github.io/nestedscales/r/reference/filter_scale.md)
to one axis and returns a new product.

## Usage

``` r
filter_product(x, axis, frame, member, ...)
```

## Arguments

- x:

  A
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

- axis:

  Axis to filter.

- frame, member:

  Passed to
  [`filter_scale()`](https://optimal2050.github.io/nestedscales/r/reference/filter_scale.md).

- ...:

  Passed to
  [`filter_scale()`](https://optimal2050.github.io/nestedscales/r/reference/filter_scale.md).

## Value

A
[`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

## Examples

``` r
p <- scale_product(a = scale_example(), b = scale_example2())
filter_product(p, "a", "sector", "P")
#> ScaleProduct: <unnamed> 
#> Axes (2):
#>   a : NestedScale 'example[sector:P]'  sector/class/group/item  leaves 4  key: item
#>   b : NestedScale 'example2'  era/period  leaves 4  key: period
#> Leaves: 4 x 4 = 16  (not materialised)
#> Coverage: a 32.3% x b 100.0% = 32.3%
```
