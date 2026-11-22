# Size of a product

**\[experimental\]** This feature may change or be removed in a later
version.

The per-axis leaf counts and their product – the number of rows a fully
dense realisation would have.

## Usage

``` r
product_size(x)
```

## Arguments

- x:

  A
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

## Value

A list with `axes` (named integer, leaves per axis) and `total` (double,
their product).

## Examples

``` r
product_size(scale_product(a = scale_example(), b = scale_example2()))
#> $axes
#> a b 
#> 7 4 
#> 
#> $total
#> [1] 28
#> 
```
