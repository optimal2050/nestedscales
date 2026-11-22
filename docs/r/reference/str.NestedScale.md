# Show the structure of a scale

Prints the tree of
[`scale_tree()`](https://optimal2050.github.io/nestedscales/r/reference/scale_tree.md):
the properties of the object, the columns of its leaftable and what a
subclass adds, each with its size and whether it is fixed, derived or
mutable. The properties themselves are read with `@` or
[`S7::prop()`](https://rconsortium.github.io/S7/reference/prop.html);
[`S7::prop_names()`](https://rconsortium.github.io/S7/reference/prop_names.html)
gives their names.

## Usage

``` r
# S3 method for class 'NestedScale'
str(object, ...)

# S3 method for class '`nestedscales::NestedScale`'
str(object, ...)

# S3 method for class '`nestedscales::ScaleProduct`'
str(object, ...)
```

## Arguments

- object:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  or a
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

- ...:

  Passed to the print method of
  [`scale_tree()`](https://optimal2050.github.io/nestedscales/r/reference/scale_tree.md).

## Value

`object`, invisibly.

## See also

[`scale_tree()`](https://optimal2050.github.io/nestedscales/r/reference/scale_tree.md)

## Examples

``` r
str(scale_example())
#> <NestedScale> example@c24a3e23
#> ├─ leaftable   data.frame [7 x 6]            one row per leaf
#> │  ├─ item     leaf column          fixed
#> │  ├─ sector   frame                fixed
#> │  ├─ class    frame                fixed
#> │  ├─ group    frame                fixed
#> │  ├─ size     weight               mutable
#> │  └─ count    weight               mutable
#> ├─ frames      chr [4]              fixed    sector, class, group, item
#> ├─ members     list [4]             derived  from leaftable: sector 2, class 3, group 3, item 7
#> ├─ leaf        chr [1]              fixed    item
#> ├─ meta        list [4]             mutable  name, desc, weights, default_weight
#> ├─ attributes  data.frame [0 x 10]  mutable  attach_attributes_scale()
#> ├─ aliases     data.frame [0 x 4]   mutable  attach_aliases_scale()
#> └─ labels      data.frame [0 x 4]   mutable  attach_labels_scale()
S7::prop_names(scale_example())
#> [1] "leaftable"  "frames"     "members"    "leaf"       "meta"      
#> [6] "attributes" "aliases"    "labels"    
```
