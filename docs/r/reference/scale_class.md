# The scale classes, for subclassing and dispatch

These return the classes
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
and
[`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md),
which are also exported under their own names. Needed to build a
subclass (`S7::new_class(..., parent = scale_class())`, which is what
[`scale_alias_property()`](https://optimal2050.github.io/nestedscales/r/reference/scale_alias_property.md)
is for) or to register an S7 method against one. To merely ask what an
object is, use
[`scale_is()`](https://optimal2050.github.io/nestedscales/r/reference/scale_is.md).

## Usage

``` r
scale_class()

scale_product_class()
```

## Value

The S7 class object.

## Examples

``` r
scale_class()
#> <nestedscales::NestedScale> class
#> @ parent     : <S7_object>
#> @ constructor: function(leaftable, frames, members, leaf, meta, attributes, aliases, labels) {...}
#> @ validator  : function(self) {...}
#> @ properties :
#>  $ leaftable: S3<data.frame>
#>  $ frames: <character> = character(0)
#>  $ members: <list> = list()
#>  $ leaf: <character> = "leaf"
#>  $ meta: <list> = list()
#>  $ attributes: <ANY> = .empty_attributes()
#>  $ aliases: <ANY> = .empty_aliases()
#>  $ labels: <ANY> = .empty_labels()
S7::S7_inherits(scale_example(), scale_class())
#> [1] TRUE
```
