# Attach physical attributes to a scale

**\[experimental\]** This feature may change or be removed in a later
version.

Appends rows to the object's attribute table. A row names the member it
belongs to (`frame`, `member`), the attribute (`attribute`, e.g.
`"lhv"`), its `kind` (see
[`SCALE_ATTRIBUTE_KINDS`](https://optimal2050.github.io/nestedscales/r/reference/SCALE_ATTRIBUTE_KINDS.md)),
its `value`, an optional `lower`/`upper` range, the physical
`unit_of_measure` (`"GJ/t"`, `"kg/TJ"`), the `source` the figure was
taken from and an optional `note`. Values can be attached at **any**
frame: a calorific value for a whole carrier is inherited by every fuel
under it that has no value of its own (see
[`scale_attributes()`](https://optimal2050.github.io/nestedscales/r/reference/scale_attributes.md)).

## Usage

``` r
attach_attributes_scale(x, attributes, source = NULL, kind = NULL)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- attributes:

  A `data.frame` with columns `frame`, `member`, `attribute`, `value`,
  `unit_of_measure`, and optionally `lower`, `upper`, `note`; `kind` and
  `source` as columns or through the arguments.

- source:

  Optional single string filled into the `source` column when
  `attributes` has none.

- kind:

  Optional single string filled into the `kind` column when `attributes`
  has none.

## Value

The scale with the rows appended.

## Details

Existing rows are never overwritten: a row whose
`(frame, member, attribute, source)` already exists is an error. Attach
a second source under its own `source` name and choose between them with
`source=` when reading.

## Examples

``` r
s <- scale_example()
s2 <- attach_attributes_scale(
  s,
  data.frame(frame = "class", member = c("G1", "G2", "S1"),
             attribute = "density", value = c(10, 20, 5),
             unit_of_measure = "t/m3"),
  source = "survey", kind = "property"
)
scale_attributes(s2, "density", frame = "item")
#>   frame member attribute     kind value lower upper unit_of_measure source note
#> 1  item     U1   density property    10    NA    NA            t/m3 survey <NA>
#> 2  item     U2   density property    10    NA    NA            t/m3 survey <NA>
#> 3  item     U3   density property    20    NA    NA            t/m3 survey <NA>
#> 4  item     U4   density property    20    NA    NA            t/m3 survey <NA>
#> 5  item     U5   density property     5    NA    NA            t/m3 survey <NA>
#> 6  item     U6   density property     5    NA    NA            t/m3 survey <NA>
#> 7  item    OTH   density     <NA>    NA    NA    NA            <NA>   <NA> <NA>
#>   origin_frame origin_member
#> 1        class            G1
#> 2        class            G1
#> 3        class            G2
#> 4        class            G2
#> 5        class            S1
#> 6        class            S1
#> 7         <NA>          <NA>
```
