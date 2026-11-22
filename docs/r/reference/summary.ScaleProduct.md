# Summarize a product

Summarize a product

## Usage

``` r
# S3 method for class 'ScaleProduct'
summary(object, ...)

# S3 method for class '`nestedscales::ScaleProduct`'
summary(object, ...)

# S3 method for class 'summary_ScaleProduct'
print(x, ...)
```

## Arguments

- object:

  A
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

- ...:

  Ignored.

- x:

  A `"summary_ScaleProduct"` object (the print method's argument).

## Value

A list of class `"summary_ScaleProduct"`: `name`, `desc`, `axes`
(per-axis summary rows), `total`, `coverage`, `joint_coverage`,
`joint_weights`.

## Examples

``` r
summary(scale_product(a = scale_example(), b = scale_example2()))
#> <summary of ScaleProduct>
#>   axes:           2
#>     a -> 'example'  4 frames, 7 leaves, key `item`
#>     b -> 'example2'  2 frames, 4 leaves, key `period`
#>   leaves:         28
```
