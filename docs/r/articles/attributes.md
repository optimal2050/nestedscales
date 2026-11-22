# Attributes, aliases and conversion

## Motivation

Figures about people are collected for places, and every table describes
the places at its own resolution: one lists cities, another regions, a
third whole countries. The numbers that turn one quantity into another –
the persons that make a household, the litres of water a person uses in
a day – are published in the same uneven way: for *some* places, and
often at a resolution other than the one the data is recorded at.

A nested scale keeps such numbers as **attributes**: values that belong
to a member at whatever frame they are published, resolved down the
hierarchy when a finer member has none of its own, and applied row by
row. The same mechanism serves any dimension – a wage per industry, an
hour count per time slice. This vignette works on people in cities.

## An example scale

Eight cities in four regions in two countries. All names and all numbers
in this vignette are invented round values, chosen for illustration;
none is a statistic. Two attributes are attached under the source
`"census"`: the persons per household (`hh_size`, in persons/household)
for six cities, and the water use per person and day (`water_use`, in
litres/person) for four.

``` r

values <- data.frame(
  frame = "city",
  member = c("Alder", "Birch", "Cedar", "Elm", "Fern", "Grove",
             "Alder", "Cedar", "Elm", "Grove"),
  attribute = rep(c("hh_size", "water_use"), c(6, 4)),
  kind = rep(c("property", "factor"), c(6, 4)),
  value = c(2, 3, 2.5, 2, 2.5, 3.5, 150, 120, 100, 200),
  unit_of_measure = rep(c("persons/household", "litres/person"), c(6, 4)),
  source = "census"
)
codes <- data.frame(
  frame = c("city", "city", "region", "country"),
  member = c("Alder", "Grove", "Harbour", "North"),
  alias = c("ALD", "GRV", "HBR", "NTH"),
  source = "short"
)
places <- scale_from_leaftable(
  data.frame(
    country = c("North", "North", "North", "North",
                "South", "South", "South", "South"),
    region = c("N1", "N1", "N2", "N2", "S1", "S1", "S1", "Harbour"),
    city = c("Alder", "Birch", "Cedar", "Dale", "Elm", "Fern", "Grove",
             "Harbour")
  ),
  frames = c("country", "region", "city"), name = "places",
  attributes = values, aliases = codes
)
places
#> NestedScale: places
#> Frames (3, coarsest first):
#>   - country (2)
#>     - region (4)
#>       - city (8)
#> Leaves: 8
#> Attributes: hh_size, water_use (sources: census) -- 10 at city
#> Aliases: 4 (short)
scale_members(places, "region")
#> [1] "N1"      "N2"      "S1"      "Harbour"
scale_children(places, "region", "S1")
#> [1] "Elm"   "Fern"  "Grove"
```

Codes repeat across frames (`Harbour` is a region and the only city
inside it), so every lookup names its frame.

Where a city has no value, there is no number – the package never fills
one in:

``` r

hh_size <- scale_attributes(places, "hh_size", frame = "city")
hh_size[c("member", "value", "unit_of_measure", "source")]
#>    member value   unit_of_measure source
#> 1   Alder   2.0 persons/household census
#> 2   Birch   3.0 persons/household census
#> 3   Cedar   2.5 persons/household census
#> 4    Dale    NA              <NA>   <NA>
#> 5     Elm   2.0 persons/household census
#> 6    Fern   2.5 persons/household census
#> 7   Grove   3.5 persons/household census
#> 8 Harbour    NA              <NA>   <NA>
```

## Attributes are not weights

A weight says *how big a leaf is*: the hours in a time slice, the area
of a region, the people of a city. Weights drive aggregation
(`weighted_mean` up) and disaggregation (`sum` split down). They are
declared on the leaftable and sum over the scale.

A household size is none of those things. It is a *conversion factor*:
it turns the households of this city into persons, row by row, and
summing it over cities is meaningless. A scale therefore keeps
attributes in a separate table, keyed by `(frame, member)`, and consumes
them only in
[`convert_scale()`](https://optimal2050.github.io/nestedscales/r/reference/convert_scale.md).
The constructor promotes numeric leaftable columns to weights; a
household size passed as a column would become a weight and be summed.
It is passed as `attributes=` instead.

Averaging an attribute over several members *is* a legitimate
aggregation – the mean household size of a region, given how many
households each of its cities has. That is an ordinary recast of a
resolved attribute with the `weighted_mean` rule, and the weight is
where weights live: on the scale, as the number of households of each
city.

``` r

s1 <- filter_scale(places, "region", "S1")
lt <- scale_leaftable(s1)
lt$households <- c(3000, 400, 2000)
south1 <- scale_from_leaftable(
  lt, frames = c("country", "region", "city"),
  attributes = scale_attributes(s1), name = "south1"
)
hh_s1 <- scale_attributes(south1, "hh_size", frame = "city")
recast_scale(
  data.frame(city = hh_s1$member, hh_size = hh_s1$value), south1,
  source = "city", target = "region", rule = "weighted_mean",
  weight = "households"
)
#>   region  hh_size
#> 1     S1 2.592593
```

([`filter_scale()`](https://optimal2050.github.io/nestedscales/r/reference/filter_scale.md)
keeps only the attribute rows of the surviving members, so the subset’s
table is exactly what the new scale may take.)

## Attributes live at any frame, and resolve by nearest ancestor

A value may be stored on a city, on a region or on a country. When a
city has no value of its own,
[`scale_attributes()`](https://optimal2050.github.io/nestedscales/r/reference/scale_attributes.md)
walks to the nearest coarser frame that holds one and reports where the
value came from. The census values are all at the city frame; a
region-wide figure from another source fills the gaps below it without
touching the cities that have their own:

``` r

regional <- attach_attributes_scale(
  places,
  data.frame(frame = "region", member = "N2", attribute = "hh_size",
             kind = "property", value = 3,
             unit_of_measure = "persons/household"),
  source = "regional"
)
res <- scale_attributes(regional, "hh_size", frame = "city")
res[res$member %in% scale_children(regional, "region", "N2"),
    c("member", "value", "source", "origin_frame", "origin_member")]
#>   member value   source origin_frame origin_member
#> 3  Cedar   2.5   census         city         Cedar
#> 4   Dale   3.0 regional       region            N2
```

`Cedar` keeps its own value; `Dale` inherits the region’s. Nothing is
guessed from a neighbouring city or an average.

Two situations are refused rather than resolved:

- **Ambiguity across a cross-cutting frame.** When the walk reaches a
  frame where the member has several ancestors and one of them holds the
  attribute, it cannot pick one and errors; if none does, it continues
  to the next coarser frame.
  [`vignette("anatomy")`](https://optimal2050.github.io/nestedscales/r/articles/anatomy.md)
  builds a scale with such a frame.
- **Several sources.** Two sources publishing the same attribute for the
  same member is an error unless `source=` chooses. The walk stays
  within the chosen source: a source that lacks a city reports `NA`
  rather than borrowing another’s figure.

In the chunk below a survey reports its own household size for `Alder`,
which the census already covers. The first read fails for that reason;
the second names the source.

``` r

two <- attach_attributes_scale(
  places,
  data.frame(frame = "city", member = "Alder", attribute = "hh_size",
             kind = "property", value = 2.2,
             unit_of_measure = "persons/household"),
  source = "survey"
)
scale_attributes(two, "hh_size", frame = "city")
#> Error:
#> ! `hh_size` for `Alder` at frame `city` is published by several sources (census, survey); pass `source=`
survey <- scale_attributes(two, "hh_size", frame = "city", source = "survey")
survey[!is.na(survey$value), c("member", "value", "source")]
#>   member value source
#> 1  Alder   2.2 survey
```

## Sources and provenance

Every attribute row names its `source` and `unit_of_measure`. Attaching
never overwrites: a row with the same
`(frame, member, attribute, source)` is an error, so a better number is
added by attaching it under its own source name and selecting it. Every
attribute name carries a `kind` (`SCALE_ATTRIBUTE_KINDS`): a `property`
is an invertible ratio, a `factor` converts one way only. Any attribute
name is accepted.

## People to households, with the household size

[`convert_scale()`](https://optimal2050.github.io/nestedscales/r/reference/convert_scale.md)
applies to each row the attribute resolved for its city. `hh_size` is
stored in persons/household, so it multiplies households into persons
and, being a `property`, divides persons into households. The two units
are matched as plain strings, exactly as they are written in
`unit_of_measure`. The result reports which value was applied and where
it came from.

``` r

pop <- data.frame(
  city     = c("Alder", "Cedar", "Elm", "Grove"),
  people_k = c(3, 5, 6, 7)
)
# thousands -> persons: no prefix arithmetic is done
pop$persons <- pop$people_k * 1e3
hh <- convert_scale(pop[c("city", "persons")], places, "hh_size",
                    from_unit = "persons", to_unit = "household")
names(hh)[names(hh) == "persons"] <- "households"
hh
#>    city households hh_size hh_size.origin_frame
#> 1 Alder       1500     2.0                 city
#> 2 Cedar       2000     2.5                 city
#> 3   Elm       3000     2.0                 city
#> 4 Grove       2000     3.5                 city
```

A `property` converts both ways, so the households return the persons:

``` r

convert_scale(hh[c("city", "households")], places, "hh_size",
              from_unit = "household", to_unit = "persons")
#>    city households hh_size hh_size.origin_frame
#> 1 Alder       3000     2.0                 city
#> 2 Cedar       5000     2.5                 city
#> 3   Elm       6000     2.0                 city
#> 4 Grove       7000     3.5                 city
```

## A city without a value

A city without a value is an error, not a silent zero. `Dale` has no
household size in the census, so a table that includes it is refused:

``` r

more <- data.frame(city = c("Cedar", "Dale"), persons = c(5000, 4000))
convert_scale(more, places, "hh_size",
              from_unit = "persons", to_unit = "household")
#> Error:
#> ! no `hh_size` value resolves for Dale at frame `city`; attach one with attach_attributes_scale() or pass na_action = "keep"
```

`na_action = "keep"` converts the rows that have a value and carries
`NA` in the others:

``` r

convert_scale(more, places, "hh_size",
              from_unit = "persons", to_unit = "household",
              na_action = "keep")
#>    city persons hh_size hh_size.origin_frame
#> 1 Cedar    2000     2.5                 city
#> 2  Dale      NA      NA                 <NA>
```

## Aggregate to regions

Aggregation is a recast with an explicit rule; `sum` conserves the
total. The rule is registered once per column, or passed as `rule=` each
time.

One decision has to be stated. The table reports four cities against a
scale of eight. By default an absent city is *unknown*, and every region
that contains one aggregates to `NA` with a warning – the safe reading
for incomplete data. Here the table is meant as the complete list of
what is to be counted, the households of the four cities and no others,
and `missing_sources = "ignore"` says so. The regional figures are then
totals of the reported cities, not estimates for the whole regions. The
warning still names the absent cities, and a region with no reported
city at all, `Harbour`, has no total.

``` r

households <- hh[c("city", "households")]
register_scale_rule("households", "sum")
by_region <- recast_scale(households, places, source = "city",
                          target = "region", missing_sources = "ignore")
#> Warning: 4 source member(s) present in the scale but missing from the data
#> (e.g. Birch, Dale, Fern, ... (4 total)); produced NAs
by_region
#>    region households
#> 1      N1       1500
#> 2      N2       2000
#> 3      S1       5000
#> 4 Harbour         NA
sum(by_region$households, na.rm = TRUE) == sum(households$households)
#> [1] TRUE
```

## Water use, one-way

A water use per person converts persons to litres and nothing else: the
litres drawn in a city say nothing certain about how many people live
there. `water_use` is therefore stored with kind `factor`, not
`property`, and
[`convert_scale()`](https://optimal2050.github.io/nestedscales/r/reference/convert_scale.md)
refuses the inverse.

``` r

water <- convert_scale(pop[c("city", "persons")], places, "water_use",
                       from_unit = "person", to_unit = "litres")
names(water)[names(water) == "persons"] <- "litres"
water
#>    city  litres water_use water_use.origin_frame
#> 1 Alder  450000       150                   city
#> 2 Cedar  600000       120                   city
#> 3   Elm  600000       100                   city
#> 4 Grove 1400000       200                   city
```

``` r

convert_scale(water[c("city", "litres")], places, "water_use",
              from_unit = "litres", to_unit = "person")
#> Error:
#> ! `water_use` converts person -> litres only; the inverse is refused because it is a factor, not a property (see SCALE_ATTRIBUTE_KINDS)
```

## Values from a published source

Reference values – the tables of a census, the results of a household
survey, the register of a single municipality – are attached the same
way: a table with one row per member and attribute, under the name of
its source. Each source is chosen with `source=` when reading; nothing
is overwritten.

``` r

own <- attach_attributes_scale(
  places,
  data.frame(frame = "city", member = "Grove", attribute = "hh_size",
             kind = "property", value = 3.4,
             unit_of_measure = "persons/household"),
  source = "register"
)
register <- scale_attributes(own, "hh_size", frame = "city",
                             source = "register")
register[!is.na(register$value), c("member", "value", "source")]
#>   member value   source
#> 7  Grove   3.4 register
```

## Names and short codes

Tables name places in different ways: one by the official name, another
by a short code.
[`scale_match()`](https://optimal2050.github.io/nestedscales/r/reference/scale_match.md)
resolves both through the alias table, exactly and case-insensitively,
first against member names and then against aliases, and reports
ambiguity instead of guessing. There is no fuzzy or substring stage: a
near miss is reported as unmatched, not repaired.

``` r

scale_match(places, c("ALD", "grove", "HBR", "Harbour", "Zed"))
#>     label  frame  member    method                   candidates
#> 1     ALD   city   Alder     alias                         <NA>
#> 2   grove   city   Grove     exact                         <NA>
#> 3     HBR region Harbour     alias                         <NA>
#> 4 Harbour   <NA>    <NA> ambiguous region/Harbour; city/Harbour
#> 5     Zed   <NA>    <NA>      none                         <NA>
scale_match(places, "Harbour", frame = "city")
#>     label frame  member method candidates
#> 1 Harbour  city Harbour  exact       <NA>
```

## Attaching the hierarchy, and colours

A table keyed by city gets its region and country with one join; the
added columns are prefixed by the scale’s name, so a second scale on the
same table never collides with the first.

``` r

join_scale(pop[c("city", "people_k")], places, frame = "city",
           attach = TRUE)
#>    city people_k places.country places.region places
#> 1 Alder        3          North            N1  Alder
#> 2 Cedar        5          North            N2  Cedar
#> 3   Elm        6          South            S1    Elm
#> 4 Grove        7          South            S1  Grove
```

Colours are presentation and are not stored on a scale. When a figure
needs them, they are joined by member name from the palette it uses –
the article *Fuels, regions and months* on the package site does so.

## Values that differ by year

The values above have no date. A household size counted in one year and
again ten years later is the same attribute of the same city with a
different *year* – a second dimension, not a deeper frame. That belongs
to a
[`scale_product()`](https://optimal2050.github.io/nestedscales/r/reference/scale_product.md)
of the scale of places and a scale of years, such as a `Calendar` from
timescales, with the values of each year attached as their own source;
it is not built in this version.

## Where next

- [`vignette("anatomy")`](https://optimal2050.github.io/nestedscales/r/articles/anatomy.md)
  takes the object apart: its tables, what the validator guarantees,
  definition files, the registry.
- The article *Fuels, regions and months* on the package site joins
  three scales of different dimensions, among them a `GeoScale` and a
  `Calendar`, on one table.
