# Open a scale-aware dataset

**\[experimental\]** This feature may change or be removed in a later
version.

## Usage

``` r
open_scale_dataset(path)

# S3 method for class 'scale_dataset'
print(x, ...)
```

## Arguments

- path:

  A folder written by
  [`write_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale_dataset.md).

- x:

  A `scale_dataset`.

- ...:

  Ignored.

## Value

A `scale_dataset`: a list with `data` (a lazily-read arrow Dataset) and
`scale` (the
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
or
[`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md)
it is indexed by). Feed them to the verbs as
`recast_scale(ds$data, ds$scale, ...)`.
[`scale_link()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md)
reports which columns of the stored data are on which scale and frame.

## Examples

``` r
# see write_scale_dataset()
```
