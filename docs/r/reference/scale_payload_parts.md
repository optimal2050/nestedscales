# Describe the parts a subclass adds to a scale

The seam a dimension package overrides so that
[`scale_tree()`](https://optimal2050.github.io/nestedscales/r/reference/scale_tree.md)
can mark the properties it adds and name its own verbs. The method
returns a data.frame with a `part` column and any of `parent`, `kind`,
`shape`, `mark`, `verb` and `note`. A row whose `part` and `parent`
match a part the core already lists replaces the fields it gives; any
other row is added. A top-level part is a property of the object;
`parent` names the property a part belongs to. `mark` is one of
`"fixed"`, `"derived"` or `"mutable"`. The `NestedScale` default adds
nothing.

## Usage

``` r
scale_payload_parts(x, ...)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- ...:

  Not used.

## Value

A data.frame of parts, or `NULL`.

## See also

[`scale_tree()`](https://optimal2050.github.io/nestedscales/r/reference/scale_tree.md)

## Examples

``` r
scale_payload_parts(scale_example())
#> NULL
```
