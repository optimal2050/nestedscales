# Weight columns of each axis

**\[experimental\]** This feature may change or be removed in a later
version.

A product has no weights of its own: the weight of a product leaf is the
product of its components' weights, which is derived when needed and
never stored.

## Usage

``` r
product_weights(x)
```

## Arguments

- x:

  A
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

## Value

A named list of character vectors.

## Examples

``` r
product_weights(scale_product(a = scale_example(), b = scale_example2()))
#> $a
#> [1] "size"  "count"
#> 
#> $b
#> [1] "span"
#> 
```
