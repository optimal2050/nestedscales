# Frames of each axis

**\[experimental\]** This feature may change or be removed in a later
version.

## Usage

``` r
product_frames(x)
```

## Arguments

- x:

  A
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

## Value

A named list of character vectors, each coarsest-first.

## Examples

``` r
product_frames(scale_product(a = scale_example(), b = scale_example2()))
#> $a
#> [1] "sector" "class"  "group"  "item"  
#> 
#> $b
#> [1] "era"    "period"
#> 
```
