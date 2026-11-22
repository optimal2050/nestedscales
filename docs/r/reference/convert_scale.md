# Convert member-keyed quantities with a member attribute

**\[experimental\]** This feature may change or be removed in a later
version.

Multiplies (or divides) the numeric value columns of `data` by the value
of `attribute` resolved for each row's member – a net calorific value to
turn mass into energy, an emission factor to turn energy into CO2, a
density to turn volume into mass. Values are resolved along the
hierarchy exactly as
[`scale_attributes()`](https://optimal2050.github.io/nestedscales/r/reference/scale_attributes.md)
does, so a factor stored on a coarser member applies to every leaf under
it that has no factor of its own.

## Usage

``` r
convert_scale(
  data,
  x,
  attribute,
  from_unit,
  to_unit,
  key = NULL,
  frame = NULL,
  values = NULL,
  source = NULL,
  na_action = c("error", "keep"),
  collect = NULL
)
```

## Arguments

- data:

  The data, in any supported backend, with a column of codes at `frame`.

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  carrying `attribute`.

- attribute:

  Name of the attribute to convert with.

- from_unit, to_unit:

  The physical units of the values before and after, matching the
  attribute's unit of measure.

- key:

  Name of the code column in `data`; defaults to `frame`.

- frame:

  Frame the codes belong to. Inferred when exactly one of the scale's
  frame names (or its leaf column) is a column of `data`.

- values:

  Value columns to convert; `NULL` takes every numeric column that is
  not the key.

- source:

  Restrict the attribute to one source; `NULL` errors on a conflict
  between sources.

- na_action:

  What to do with rows whose member has no value: `"error"` (default) or
  `"keep"` (an `NA` result).

- collect:

  For lazy inputs: materialise (`TRUE`) or return the query.

## Value

`data` with the value columns converted, plus two columns named after
the attribute: `<attribute>` (the factor applied) and
`<attribute>.origin_frame` (the frame the factor was taken from), in the
input's class.

## Details

Direction comes from the attribute's unit of measure, read as
`"<numerator>/<denominator>"`: with `lhv` in `"GJ/t"`,
`from_unit = "t", to_unit = "GJ"` multiplies, and
`from_unit = "GJ", to_unit = "t"` divides. The inverse is allowed only
when the attribute's `kind` is `"property"`; a `"factor"` is one-way. No
unit-prefix arithmetic is done: a column in kilotonnes must be turned
into tonnes before converting with a GJ/t factor.

A member for which no value resolves is an **error** by default – a
silently dropped row is a wrong total – unless `na_action = "keep"`,
which leaves `NA` in its rows.

## Examples

``` r
s <- attach_attributes_scale(
  scale_example(),
  data.frame(frame = c("sector", "item"), member = c("P", "U5"),
             attribute = "pack_size", value = c(20, 30),
             unit_of_measure = "pieces/box"),
  source = "example", kind = "property"
)
boxes <- data.frame(item = c("U1", "U2", "U5"), n = c(100, 200, 50))
pieces <- convert_scale(boxes, s, attribute = "pack_size",
                        from_unit = "box", to_unit = "pieces")
pieces
#>   item    n pack_size pack_size.origin_frame
#> 1   U1 2000        20                 sector
#> 2   U2 4000        20                 sector
#> 3   U5 1500        30                   item
# back to boxes: a property is invertible
convert_scale(pieces[c("item", "n")], s, attribute = "pack_size",
              from_unit = "pieces", to_unit = "box")
#>   item   n pack_size pack_size.origin_frame
#> 1   U1 100        20                 sector
#> 2   U2 200        20                 sector
#> 3   U5  50        30                   item
```
