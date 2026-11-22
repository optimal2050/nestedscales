# Is this a scale, or a product of scales?

These are how calling code asks what an object is. Build a scale with
[`scale_from_leaftable()`](https://optimal2050.github.io/nestedscales/r/reference/scale_from_leaftable.md)
and a product with
[`scale_product()`](https://optimal2050.github.io/nestedscales/r/reference/scale_product.md).

## Usage

``` r
scale_is(x)

scale_is_product(x)
```

## Arguments

- x:

  Any object.

## Value

A single `TRUE` or `FALSE`. A product is NOT a scale: it holds several
and materialises no leaves of its own.

## Details

Named with the object prefix rather than `is_scale()`, which `ggplot2`
already exports.

## Examples

``` r
scale_is(scale_example())
#> [1] TRUE
scale_is(data.frame(item = "U1"))
#> [1] FALSE
scale_is_product(scale_product(a = scale_example(), b = scale_example2()))
#> [1] TRUE
```
