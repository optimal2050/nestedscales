# The data key column of each axis

**\[experimental\]** This feature may change or be removed in a later
version.

Data on a product carries one of these columns per axis.

## Usage

``` r
product_keys(x)
```

## Arguments

- x:

  A
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

## Value

A named character vector, axis -\> column name.

## Examples

``` r
product_keys(scale_product(a = scale_example(), b = scale_example2()))
#>        a        b 
#>   "item" "period" 
```
