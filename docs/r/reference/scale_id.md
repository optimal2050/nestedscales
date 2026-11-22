# The identity of a scale

A short string that says which scale an object is: its name and a hash
of its structure, `"<name>@<hash>"`. The hash covers the leaf column,
the frames and the leaf-to-frame memberships; weights, attributes,
aliases, labels and the order of rows or members do not enter, so adding
a weight keeps data bound to the scale valid, while a subset or a
re-grouping is a different scale. A data link compares the hash alone:
two objects with the same structure under different names are the same
scale to it, and the name is kept for messages.

## Usage

``` r
scale_id(x)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

## Value

A single string.

## Details

The hash is the first eight hexadecimal digits of the MD5 of a canonical
UTF-8 text: the line `key=<leaf column name>` (the prefix `key=` is part
of the hashed text and is kept so that identities do not change), the
line `frames=` with the frame names tab-separated, then one
tab-separated line per leaf (its code in the leaf column first, then its
code at each frame, empty where unassigned), leaves sorted by the leaf
column in the C locale, lines joined by `"\n"`.

## See also

[`bind_scale()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md)

## Examples

``` r
scale_id(scale_example())
#> [1] "example@c24a3e23"
```
