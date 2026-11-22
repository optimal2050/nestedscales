# nestedscales

Documentation: <https://optimal2050.github.io/nestedscales/r/>

nestedscales provides the machinery for describing one dimension of data
at several resolutions at once, and for moving data between those
resolutions by explicit rules.

Models and statistics rarely use a dimension at a single resolution.
Time is needed in hours and in months, space in cities and in countries,
the economy in activities and in sectors, and data usually arrives at a
resolution other than the one in use. A **nested scale** is the record
that makes the conversion possible: it lists the finest items of a
dimension and how they group, step by step, into coarser ones. With that
record, a table of values at one resolution is converted to any other:
summed, averaged with weights, copied down, or split in proportion.

The package is the common base of
[timescales](https://github.com/optimal2050/timescales) (calendars) and
[geoscales](https://github.com/optimal2050/geoscales) (regions), and
serves any other dimension declared from a table.

## What a nested scale is

One dimension, here space, described at three resolutions, and the same
data at each of them:

``` R
 the scale     frame      members
               -------    -------------------------------------------------
 coarse        country    [          North          ]  [       South      ]
               region     [    N1    ]  [    N2     ]  [        S1        ]
 fine          city       [ a ]  [ b ]  [ c ]  [ d  ]  [ e ]  [ f ]  [ g  ]

 data on it               (people, moved between the frames by the rule "sum")
               -------    -------------------------------------------------
               city         3      2      5      4       6      1      7
               region          5             9                 14
               country               14                        14
```

- A **frame** is one resolution of the dimension: `country`, `region`,
  `city`.
- A **member** is one item of a frame: `North`, `N1`, `a`.
- The **leaves** are the members of the finest frame, the cities. The
  scale stores one row per leaf with its member at every frame.
- **Nesting** is what the boxes show: every member of a finer frame lies
  inside exactly one member of the coarser frame, so a value on cities
  has one place to go at the region and at the country.
- The **nested scale** is the whole of it: the frames, their members,
  and which leaf belongs to which.

``` r

library(nestedscales)

places <- scale_from_leaftable(
  data.frame(
    country = c("North", "North", "North", "North", "South", "South", "South"),
    region  = c("N1", "N1", "N2", "N2", "S1", "S1", "S1"),
    city    = c("a", "b", "c", "d", "e", "f", "g")
  ),
  frames = c("country", "region", "city"), name = "places"
)
places
#> NestedScale: places
#> Frames (3, coarsest first):
#>   - country (2)
#>     - region (3)
#>       - city (7)
#> Leaves: 7

people <- data.frame(city = c("a", "b", "c", "d", "e", "f", "g"),
                     people = c(3, 2, 5, 4, 6, 1, 7))
recast_scale(people, places, source = "city", target = "region",
             rule = "sum")
#>   region people
#> 1     N1      5
#> 2     N2      9
#> 3     S1     14
recast_scale(people, places, source = "city", target = "country",
             rule = "sum")
#>   country people
#> 1   North     14
#> 2   South     14
```

A scale may also hold frames that do not nest in the others, such as a
grouping of the same cities by river basin. Conversion always passes
through the leaves, so such a frame is used in the same way.

The package defines:

- **Structure**: the frames of a scale, the members at each frame, and
  the relations between frames (nested, crossed, uniform).
- **Transition rules** between frames, chosen per value column and aware
  of direction: `sum`, `weighted_mean`, `mean`, and `copy`; `sd` for
  aggregation; and `share` or `logshare` for within-parent shares.
- **Operations**: converting data between frames, attaching frame labels
  to a dataset, subsetting, combining several scales into one
  multi-dimensional index, clustering members into new frames, and
  storing data together with its scales.
- **Labels, attributes and definitions**: display names for members and
  frames, in named variants; values that belong to a member but are not
  weights (the persons per household of a city, a wage per employee),
  resolved along the hierarchy and applied row by row; alternative
  spellings matched strictly; and language-neutral definition files,
  with a catalogue of the ones installed packages ship.
- **A link between data and scale** (experimental): the code columns of
  a table can record which scale and frame they are on, so a conversion
  is refused for data of another scale.

The package is dimension-agnostic. Time and space are provided by two
packages built on it, designed for optimization and simulation models,
where labeled time slices and regions serve as the index sets of
variables and constraints:

- [timescales](https://github.com/optimal2050/timescales): `Calendar`,
  labeled discrete time slices (hours, days, seasons, representative
  days).
- [geoscales](https://github.com/optimal2050/geoscales): `GeoScale`,
  labeled geographical regions with geometry.

Both classes are subclasses of `NestedScale`. Any other dimension
(industries, income brackets, technology vintages) is declared directly
from a table.
[`vignette("nestedscales")`](https://optimal2050.github.io/nestedscales/r/articles/nestedscales.md)
introduces the functions; the [package
website](https://optimal2050.github.io/nestedscales/) includes a roadmap
of what is available and what is planned.

## Installation

The released version is on CRAN:

``` r

install.packages("nestedscales")
```

The development version is on GitHub:

``` r

pak::pkg_install("optimal2050/nestedscales")
```

The package is pure R; its non-base runtime dependencies are dplyr,
rlang, S7, vctrs and jsonlite.

## A scale in one call

Declare the frames, coarsest first:

``` r

library(nestedscales)

industries <- data.frame(
  section  = c("C", "C", "C", "D", "D"),
  division = c("C10", "C10", "C11", "D35", "D35"),
  class    = c("C101", "C102", "C110", "D351", "D352"),
  gva      = c(120, 80, 45, 300, 150)
)

ind <- scale_from_leaftable(
  industries,
  frames = c("section", "division", "class"),
  weights = "gva",
  name   = "nace"
)

ind
#> NestedScale: nace
#> Frames (3, coarsest first):
#>   - section (2)
#>     - division (3)
#>       - class (5)
#> Leaves: 5
#> Weights: gva (default: gva)
```

Every structural question is answered from the leaves, never from an
assumed tree:

``` r

scale_frames(ind)
#> [1] "section"  "division" "class"
scale_members(ind, "division")
#> [1] "C10" "C11" "D35"
scale_nests(ind, "section", "division")
#> [1] TRUE
```

Hierarchies that cross-cut are normal and supported – one detailed code
may belong to several aggregates. `scale_nests(x, parent, child)` tests
whether every child code belongs to a single parent code; conversion
never depends on that relationship.

``` r

summary(ind)
#> <summary of NestedScale 'nace'>
#>   frames:         section (2) / division (3) / class (5)
#>   leaves:         5
#>   weight totals:  gva = 695  (default: gva)
#>   nesting:        section > division: nested
#>   nesting:        division > class: nested
```

## Moving data between frames

Data keyed at one frame is recast to another with a rule per value
column. With complete coverage, `"sum"` conserves totals; intensive
quantities use `"weighted_mean"` with a declared weight:

``` r

x <- data.frame(
  class = c("C101", "C102", "C110", "D351", "D352"),
  jobs  = c(12, 8, 5, 30, 20),
  wage  = c(31, 29, 27, 45, 40)
)

recast_scale(x, ind, source = "class", target = "section",
             rule = c(jobs = "sum", wage = "weighted_mean"),
             weight = "gva")
#>   section jobs     wage
#> 1       C   25 29.61224
#> 2       D   50 43.33333
```

## The same on time

Time is a dimension like any other: minutes group into hours, hours into
days. The scale below has two days of 24 hours of 60 minutes, one row
per minute, and a count per minute is summed to hours and to days.

``` r

grid <- expand.grid(m = 0:59, h = 0:23, d = 1:2)
clock <- data.frame(
  day    = sprintf("d%d", grid$d),
  hour   = sprintf("d%d_h%02d", grid$d, grid$h),
  minute = sprintf("d%d_h%02d_m%02d", grid$d, grid$h, grid$m)
)
time <- scale_from_leaftable(clock, frames = c("day", "hour", "minute"),
                             name = "clock")

visitors <- data.frame(minute = clock$minute, visitors = grid$h %/% 6 + 1)
head(recast_scale(visitors, time, source = "minute", target = "hour",
                  rule = "sum"), 3)
#>     hour visitors
#> 1 d1_h00       60
#> 2 d1_h01       60
#> 3 d1_h02       60
recast_scale(visitors, time, source = "minute", target = "day",
             rule = "sum")
#>   day visitors
#> 1  d1     3600
#> 2  d2     3600
```

This is only the bare mechanism.
[timescales](https://github.com/optimal2050/timescales) builds on it for
calendars with real dates, time zones, months of unequal length and
typical or sampled periods.

## Definition files and attributes

Scales travel as definition files (a JSON header with the tables inline,
or a bundle with Arrow or CSV tables) that the Python binding reads as
well. A scale may also carry values that belong to its members, such as
the persons per household of a city, and alternative names for them. The
values below are invented.

``` r

places <- attach_attributes_scale(
  places,
  data.frame(frame = c("region", "city"), member = c("N1", "e"),
             attribute = "hh_size", kind = "property", value = c(2.5, 2),
             unit_of_measure = "persons/household"),
  source = "example"
)
places <- attach_aliases_scale(
  places,
  data.frame(frame = "city", member = "a", alias = "Alder"),
  source = "example"
)
file <- tempfile(fileext = ".json")
write_scale(places, file)
places <- read_scale(file)
places
#> NestedScale: places
#> Frames (3, coarsest first):
#>   - country (2)
#>     - region (3)
#>       - city (7)
#> Leaves: 7
#> Attributes: hh_size (sources: example) -- 1 at region, 1 at city
#> Aliases: 1 (example)

households <- convert_scale(people[c(1, 2, 5), ], places, "hh_size",
                            from_unit = "persons", to_unit = "household")
names(households)[names(households) == "people"] <- "households"
households
#>   city households hh_size hh_size.origin_frame
#> 1    a        1.2     2.5               region
#> 2    b        0.8     2.5               region
#> 3    e        3.0     2.0                 city

scale_match(places, c("Alder", "B", "Zed"))
#>   label frame member method candidates
#> 1 Alder  city      a  alias       <NA>
#> 2     B  city      b  exact       <NA>
#> 3   Zed  <NA>   <NA>   none       <NA>
```

[`scale_attributes()`](https://optimal2050.github.io/nestedscales/r/reference/scale_attributes.md)
resolves a value for every member of a frame, walking to the nearest
coarser frame that holds one, so the cities `a` and `b` take the
household size of their region. With the people counted in thousands,
the converted column holds thousands of households.
[`scale_match()`](https://optimal2050.github.io/nestedscales/r/reference/scale_match.md)
resolves names and codes through the alias table, strictly.

## Design

- **A scale is a definition, not a container.** It holds the leaves, the
  frames that group them and the weights that size them. Data stays in
  ordinary tables and is matched to a scale by its codes; the
  experimental
  [`bind_scale()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md)
  can also record on the code columns which scale and frame they are on.
- **Leaves are the ground truth.** Frames are partitions of the leaves,
  not necessarily a strict tree; conversion always routes through the
  leaf layer.
- **Weights are named and plural.** A scale can carry `gva`,
  `employment` and `count` side by side, with one declared default.
- **Attributes are not weights.** A weight says how big a leaf is and
  drives aggregation; an attribute is a per-member factor, consumed row
  by row and never summed.
- **Partial coverage is first class.** A leaf with no code at a frame is
  `NA`, not an error, and a subset records what fraction of its parent
  it keeps.
- **Backend-agnostic.** The verbs use the dplyr interface, so the same
  pipeline runs on a `data.frame`, a `data.table`, or an arrow dataset;
  lazy inputs stay lazy.

## Related packages

- [scales](https://CRAN.R-project.org/package=scales) maps data to
  graphical aesthetics; its discrete scales are palettes and label
  formatters, not resolutions of a model dimension.
- [data.tree](https://CRAN.R-project.org/package=data.tree) represents
  strict trees as node objects. nestedscales keeps the hierarchy as a
  flat leaf table, allows frames that cross-cut, and converts data
  between any two frames with weights.
- [hts](https://CRAN.R-project.org/package=hts) reconciles forecasts
  across a fixed aggregation tree;
  [`reconcile_scale()`](https://optimal2050.github.io/nestedscales/r/reference/reconcile_scale.md)
  here compares data aggregated with `sum` or `weighted_mean` against
  independent totals and can balance discrepancies.

## License

Apache License 2.0.
