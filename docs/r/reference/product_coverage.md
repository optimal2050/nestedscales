# Coverage of each axis

**\[experimental\]** This feature may change or be removed in a later
version.

Sampling is per-axis and independent, so the coverage of the product is
the product of its axes' coverages – `prod(product_coverage(p))`.

## Usage

``` r
product_coverage(x, weight = NULL)
```

## Arguments

- x:

  A
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

- weight:

  Optional weight name, applied to every axis. `NULL` uses each axis's
  own default weight.

## Value

A named numeric, one entry per axis.

## Examples

``` r
p <- scale_product(a = scale_example(), b = scale_example2())
product_coverage(p)
#> a b 
#> 1 1 
prod(product_coverage(p))
#> [1] 1
```
