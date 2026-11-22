# A product of several scales (S7 class)

**\[experimental\]** This feature may change or be removed in a later
version.

Combines two or more
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
objects into one multi-dimensional index – time x space, time x space x
industry, and so on. The leaves of the product are tuples of the
component leaves, and they stay LAZY: nothing is materialised at
construction, and
[`product_leaves()`](https://optimal2050.github.io/nestedscales/r/reference/product_leaves.md)
is the guarded way to realise them.

## Usage

``` r
ScaleProduct(axes, keys, joint_weights = NULL, meta = list())
```

## Arguments

- axes:

  Named list of
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  objects; the names are the axis names.

- keys:

  Named character vector, one entry per axis, giving the data column
  that carries that axis's member codes.

- joint_weights:

  Reserved for a weight that varies jointly across axes (an hourly
  profile used as a spatial split weight). `NULL` in this version; a
  supplied table is validated but not yet consumed.

- meta:

  Named list of attributes (`name`, `desc`).

## Value

A `ScaleProduct` object.

## Details

Construct with
[`scale_product()`](https://optimal2050.github.io/nestedscales/r/reference/scale_product.md).

## See also

[`scale_product()`](https://optimal2050.github.io/nestedscales/r/reference/scale_product.md),
[`product_leaves()`](https://optimal2050.github.io/nestedscales/r/reference/product_leaves.md),
[`product_size()`](https://optimal2050.github.io/nestedscales/r/reference/product_size.md)

## Examples

``` r
scale_product(a = scale_example(), b = scale_example2())
#> ScaleProduct: <unnamed> 
#> Axes (2):
#>   a : NestedScale 'example'  sector/class/group/item  leaves 7  key: item
#>   b : NestedScale 'example2'  era/period  leaves 4  key: period
#> Leaves: 7 x 4 = 28  (not materialised)
```
