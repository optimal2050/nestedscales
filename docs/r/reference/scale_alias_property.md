# An alias property for a subclass

Builds a getter/setter property that reads and writes an inherited
property under a different name – how timescales' `Calendar` keeps
`@timeframes` and geoscales' `Geoscale` keeps `@geoframes` working over
the inherited `@frames`, so no existing code has to change when they
become subclasses.

## Usage

``` r
scale_alias_property(name)
```

## Arguments

- name:

  Name of the inherited property to alias.

## Value

An S7 property.

## Details

The setter is a no-op on `NULL`. S7's generated constructor writes every
dynamic property once with `NULL` before the real values are set, so a
setter that forwards `NULL` makes the class impossible to construct.

## Examples

``` r
Aliased <- S7::new_class("Aliased",
  parent = scale_class(),
  properties = list(levels = scale_alias_property("frames"))
)
a <- Aliased(
  leaftable = scale_leaftable(scale_example()),
  frames = scale_frames(scale_example()),
  members = S7::prop(scale_example(), "members"),
  leaf = scale_leaf_column(scale_example())
)
a@levels
#> [1] "sector" "class"  "group"  "item"  
```
