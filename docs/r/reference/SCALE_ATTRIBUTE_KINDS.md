# Kinds of attribute

**\[experimental\]** This feature may change or be removed in a later
version.

Every attribute name carries a kind, which
[`convert_scale()`](https://optimal2050.github.io/nestedscales/r/reference/convert_scale.md)
consults:

## Usage

``` r
SCALE_ATTRIBUTE_KINDS
```

## Format

A character vector of length 2.

## Value

A character vector of the two attribute kinds accepted in the `kind`
column of
[`attach_attributes_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_attributes_scale.md):
`"property"` and `"factor"`.

## Details

- `property`:

  A physical property of the member, an invertible ratio: a calorific
  value in GJ/t converts tonnes to gigajoules and gigajoules back to
  tonnes; a density, a yield.

- `factor`:

  A one-way multiplier: an emission factor in kg/TJ turns energy into
  CO2, and there is no physical sense in which CO2 turns back into
  energy; a loss factor, a tax rate.

## Examples

``` r
SCALE_ATTRIBUTE_KINDS
#> [1] "property" "factor"  
```
