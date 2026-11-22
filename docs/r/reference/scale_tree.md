# The parts of a scale and which of them may change

Lists the parts of a scale as a tree: its properties, the columns of the
leaftable, and whatever a subclass adds. Each part carries one of three
marks, defined by the identity of the scale
([`scale_id()`](https://optimal2050.github.io/nestedscales/r/reference/scale_id.md)),
which is computed from the leaf column, the frame names and the frame
codes:

## Usage

``` r
scale_tree(x)

# S3 method for class 'scale_tree'
print(x, ascii = !isTRUE(l10n_info()[["UTF-8"]]), ...)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  or a
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md);
  in [`print()`](https://rdrr.io/r/base/print.html), the table
  `scale_tree()` returned.

- ascii:

  Draw the branches with `+`, `-` and `|`. The default does so outside a
  UTF-8 session.

- ...:

  Ignored.

## Value

A data.frame of class `scale_tree`, one row per part: `part`, the
`parent` property it belongs to (`""` for a property), its `kind`,
`shape`, `mark`, the `verb` that changes it and a `note`. Printing it
draws the tree.

## Details

- `fixed`: the part enters the identity. Changing it gives another
  scale, which data bound to the first one no longer matches; the route
  is to build a new scale.

- `derived`: the part is computed from another one and is never set.

- `mutable`: the part can change and the scale stays the same scale. The
  function that changes it is named where there is one.

The marks describe the object; they are not enforced on assignment.
[`str()`](https://rdrr.io/r/utils/str.html) on a scale prints the same
tree.

## See also

[`scale_id()`](https://optimal2050.github.io/nestedscales/r/reference/scale_id.md),
[`scale_payload_parts()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_parts.md)

## Examples

``` r
scale_tree(scale_example())
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
tr <- scale_tree(scale_example())
tr$part[tr$mark == "fixed"]
#> [1] "item"   "sector" "class"  "group"  "frames" "leaf"  
scale_tree(scale_product(a = scale_example(), b = scale_example2()))
#> <ScaleProduct>
#> ├─ axes           list [2]                   one scale per axis
#> │  ├─ a           axis NestedScale  fixed    example@c24a3e23
#> │  └─ b           axis NestedScale  fixed    example2@f6854959
#> ├─ keys           chr [2]           fixed    a = item, b = period
#> ├─ joint_weights  NULL              mutable  reserved
#> └─ meta           list [2]          mutable  name, desc
```
