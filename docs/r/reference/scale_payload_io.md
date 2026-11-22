# Write and read a subclass's payload in a definition file

The seam a dimension package uses to carry what the core does not know
about – `geoscales`' geometry – in a scale definition written by
[`write_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
and read by
[`read_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md).

## Usage

``` r
scale_write_payload(x, ...)

scale_read_payload(x, ...)

register_scale_class(class)

list_scale_classes()
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  (the subclass instance when writing; the core object when reading).

- ...:

  Method arguments: `dir`, the bundle directory or `NULL`, and `header`,
  the header list.

- class:

  An S7 class that inherits from
  [`scale_class()`](https://optimal2050.github.io/nestedscales/r/reference/scale_class.md).

## Value

`scale_write_payload()` the header; `scale_read_payload()` a scale;
`register_scale_class()` the registry key, invisibly;
`list_scale_classes()` a character vector of registered class names.

## Details

`scale_write_payload(x, dir, header)` is called after the core tables
are written, with the bundle directory (`NULL` for a single-file
definition, which can hold inline data only) and the header so far; it
writes its files and returns the header with its entries added under
`payload`. `scale_read_payload(x, dir, header)` is called with the CORE
scale rebuilt from the header and returns the subclass object. The
`NestedScale` defaults return the header and `x` unchanged.

[`read_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
finds the method through the class recorded in the header, so a
dimension package registers its class once, in `.onLoad()`, with
`register_scale_class()`.

## Examples

``` r
list_scale_classes()
#> character(0)
```
