# Combine scales into a product index

**\[experimental\]** This feature may change or be removed in a later
version.

## Usage

``` r
scale_product(..., name = "", desc = "", keys = NULL, joint_weights = NULL)
```

## Arguments

- ...:

  Two or more named
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  objects; the argument names become the axis names.

- name, desc:

  Short name and description of the product.

- keys:

  Optional named character vector overriding the data key column per
  axis. By default each axis uses the name of its scale's leaf column
  ([`scale_leaf_column()`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaf_column.md));
  if that would make two axes share a column name, the AXIS NAMES are
  used instead.

- joint_weights:

  Reserved; see
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

## Value

A
[`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

## Examples

``` r
p <- scale_product(a = scale_example(), b = scale_example2())
p
#> ScaleProduct: <unnamed> 
#> Axes (2):
#>   a : NestedScale 'example'  sector/class/group/item  leaves 7  key: item
#>   b : NestedScale 'example2'  era/period  leaves 4  key: period
#> Leaves: 7 x 4 = 28  (not materialised)
product_size(p)
#> $axes
#> a b 
#> 7 4 
#> 
#> $total
#> [1] 28
#> 
```
