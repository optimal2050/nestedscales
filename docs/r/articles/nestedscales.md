# Get started with nestedscales

nestedscales provides a discrete representation of a data dimension at
several resolutions and the operations that move data between them. This
vignette introduces the representation and the main functions on a small
industry classification. The dimension packages
[timescales](https://github.com/optimal2050/timescales) and
[geoscales](https://github.com/optimal2050/geoscales) apply the same
functions to calendars and region hierarchies. The [package
website](https://optimal2050.github.io/nestedscales/) includes a roadmap
of the package’s scope.

``` r

library(nestedscales)
```

## Representation

A **nested scale** is a table with one row per leaf, the finest member
of the dimension, and one column per frame, a resolution at which the
leaves are grouped. The frames are given coarsest first. Numeric columns
that are not frames are weights.

``` r

industries <- data.frame(
  section  = c("C", "C", "C", "D", "D"),
  division = c("C10", "C10", "C11", "D35", "D35"),
  class    = c("C101", "C102", "C110", "D351", "D352"),
  gva      = c(120, 80, 45, 300, 150)
)

ind <- scale_from_leaftable(
  industries,
  frames = c("section", "division", "class"),
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

The scale records the frames, the members at each frame, the leaf column
and the weights:

``` r

scale_frames(ind)
#> [1] "section"  "division" "class"
scale_members(ind, "division")
#> [1] "C10" "C11" "D35"
scale_leaf_column(ind)
#> [1] "class"
scale_weights(ind)
#> [1] "gva"
```

Every frame partitions the leaves. Frames need not nest in each other: a
member at one frame may belong to several members at a coarser frame,
and two frames may be independent, in which case the leaves are their
combinations.
[`scale_nests()`](https://optimal2050.github.io/nestedscales/r/reference/scale_nests.md),
[`scale_crosses()`](https://optimal2050.github.io/nestedscales/r/reference/scale_crosses.md)
and
[`scale_is_uniform()`](https://optimal2050.github.io/nestedscales/r/reference/scale_is_uniform.md)
report the relation a given pair of frames has; no relation is assumed.

``` r

scale_nests(ind, "section", "division")
#> [1] TRUE
scale_family(ind, "section", "division")
#>   parent_frame parent child_frame child
#> 1      section      C    division   C10
#> 2      section      C    division   C11
#> 3      section      D    division   D35
```

## Transition rules

Data keyed at one frame is converted to another frame with
[`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md).
Each value column follows a rule from `SCALE_RULES`:

| rule | aggregation (fine to coarse) | disaggregation (coarse to fine) |
|----|----|----|
| `sum` | sum | split in proportion to the weight |
| `weighted_mean` | weighted mean | copy |
| `mean` | mean over leaves | copy |
| `copy` | the common value | copy |
| `sd` | standard deviation over leaves | not defined |
| `share` | value as a share of its parent’s total | not defined |

The rule is given per value column, so extensive and intensive
quantities convert in one call:

``` r

x <- data.frame(
  class = c("C101", "C102", "C110", "D351", "D352"),
  jobs  = c(12, 8, 5, 30, 20),
  wage  = c(31, 29, 27, 45, 40)
)

recast_scale(x, ind,
  source = "class", target = "section",
  rule = c(jobs = "sum", wage = "weighted_mean")
)
#>   section jobs     wage
#> 1       C   25 29.61224
#> 2       D   50 43.33333
```

The same function converts in the other direction. A total at the
section frame is split over the classes in proportion to the weight:

``` r

y <- data.frame(section = c("C", "D"), investment = c(100, 400))

recast_scale(y, ind, source = "section", target = "class", rule = "sum")
#>   class investment
#> 1  C101   48.97959
#> 2  C102   32.65306
#> 3  C110   18.36735
#> 4  D351  266.66667
#> 5  D352  133.33333
```

Columns that are neither the key nor a value column are identifiers and
are preserved as groups, so a panel of several years or scenarios
converts in one call. A rule may also be registered once for a named
value column with
[`register_scale_rule()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_rule.md),
after which `rule =` can be omitted for that column.

## The same on time

Nothing above is specific to industries. Time is a dimension like any
other: minutes group into hours and hours into days. The scale below is
built from a table generated in code, two days of 24 hours of 60
minutes, with one row per minute. The codes of the hours and of the
minutes include the day, so that every code names one member.

``` r

grid <- expand.grid(m = 0:59, h = 0:23, d = 1:2)
clock <- data.frame(
  day    = sprintf("d%d", grid$d),
  hour   = sprintf("d%d_h%02d", grid$d, grid$h),
  minute = sprintf("d%d_h%02d_m%02d", grid$d, grid$h, grid$m)
)
time <- scale_from_leaftable(clock, frames = c("day", "hour", "minute"),
                             name = "clock")
time
#> NestedScale: clock
#> Frames (3, coarsest first):
#>   - day (2)
#>     - hour (48)
#>       - minute (2880)
#> Leaves: 2880
```

A series recorded per minute is recast to hours and to days. A count,
here the visitors entering a shop, is summed; a reading, here the
temperature of the room, is averaged. Both series are invented.

``` r

series <- data.frame(
  minute   = clock$minute,
  visitors = grid$h %/% 6 + 1,
  temp     = 18 + grid$h / 4
)
head(series, 3)
#>       minute visitors temp
#> 1 d1_h00_m00        1   18
#> 2 d1_h00_m01        1   18
#> 3 d1_h00_m02        1   18

hourly <- recast_scale(series, time, source = "minute", target = "hour",
                       rule = c(visitors = "sum", temp = "mean"))
head(hourly, 3)
#>     hour visitors  temp
#> 1 d1_h00       60 18.00
#> 2 d1_h01       60 18.25
#> 3 d1_h02       60 18.50

recast_scale(series, time, source = "minute", target = "day",
             rule = c(visitors = "sum", temp = "mean"))
#>   day visitors   temp
#> 1  d1     3600 20.875
#> 2  d2     3600 20.875
```

The hourly table moves on in the same way, since `hour` is a frame like
any other:

``` r

recast_scale(hourly[c("hour", "visitors")], time,
             source = "hour", target = "day", rule = "sum")
#>   day visitors
#> 1  d1     3600
#> 2  d2     3600
```

This example is only the bare mechanism: its minutes carry no dates, and
every hour and every day has the same length.
[timescales](https://github.com/optimal2050/timescales) builds on it for
calendars with real dates, time zones, months of unequal length and
typical or sampled periods.

## Labels

[`join_scale()`](https://optimal2050.github.io/nestedscales/r/reference/join_scale.md)
attaches the scale’s labels to a dataset: the member at the keyed frame,
optionally the coarser frames (`attach =`) and the member’s share and
weight (`meta =`):

``` r

join_scale(x, ind, frame = "class", attach = TRUE)
#>   class jobs wage nace.section nace.division nace
#> 1  C101   12   31            C           C10 C101
#> 2  C102    8   29            C           C10 C102
#> 3  C110    5   27            C           C11 C110
#> 4  D351   30   45            D           D35 D351
#> 5  D352   20   40            D           D35 D352
```

## Subsets

[`filter_scale()`](https://optimal2050.github.io/nestedscales/r/reference/filter_scale.md)
keeps the leaves under given members; the result records what fraction
of each weight it retains.
[`prune_scale()`](https://optimal2050.github.io/nestedscales/r/reference/prune_scale.md)
collapses a scale to a coarser leaf frame.

``` r

manufacturing <- filter_scale(ind, "section", "C")
scale_members(manufacturing)
#> [1] "C101" "C102" "C110"
scale_coverage(manufacturing)
#>      gva 
#> 0.352518

scale_frames(prune_scale(ind, "division"))
#> [1] "section"  "division"
```

## Attributes and aliases

A scale may carry values that belong to its members but are not weights:
the persons per household of a city, a price per item, a wage per
employee. They live in an attribute table keyed by `(frame, member)`, at
whatever frame they are published, and
[`scale_attributes()`](https://optimal2050.github.io/nestedscales/r/reference/scale_attributes.md)
resolves one value per member of a frame, walking to the nearest coarser
frame when a member has none of its own.
[`convert_scale()`](https://optimal2050.github.io/nestedscales/r/reference/convert_scale.md)
applies the resolved value row by row. Alternative names live in an
alias table, and
[`scale_match()`](https://optimal2050.github.io/nestedscales/r/reference/scale_match.md)
resolves names against member names and aliases exactly, reporting
ambiguity rather than guessing. A small scale of cities shows all three:
seven cities in three regions in two countries, with a household size
for region `N1` and for city `e`, and a longer name for city `a`. The
values are invented.

``` r

places <- scale_from_leaftable(
  data.frame(
    country = c("North", "North", "North", "North", "South", "South", "South"),
    region  = c("N1", "N1", "N2", "N2", "S1", "S1", "S1"),
    city    = c("a", "b", "c", "d", "e", "f", "g")
  ),
  frames = c("country", "region", "city"), name = "places",
  attributes = data.frame(
    frame = c("region", "city"), member = c("N1", "e"),
    attribute = "hh_size", kind = "property", value = c(2.5, 2),
    unit_of_measure = "persons/household", source = "example"
  ),
  aliases = data.frame(frame = "city", member = "a", alias = "Alder",
                       source = "example")
)
scale_attributes(places, "hh_size", frame = "city")[
  c("member", "value", "unit_of_measure", "origin_frame")]
#>   member value   unit_of_measure origin_frame
#> 1      a   2.5 persons/household       region
#> 2      b   2.5 persons/household       region
#> 3      c    NA              <NA>         <NA>
#> 4      d    NA              <NA>         <NA>
#> 5      e   2.0 persons/household         city
#> 6      f    NA              <NA>         <NA>
#> 7      g    NA              <NA>         <NA>

people <- data.frame(city = c("a", "b", "e"), people = c(3, 2, 6))
convert_scale(people, places, "hh_size",
              from_unit = "persons", to_unit = "household")
#>   city people hh_size hh_size.origin_frame
#> 1    a    1.2     2.5               region
#> 2    b    0.8     2.5               region
#> 3    e    3.0     2.0                 city

scale_match(places, c("Alder", "B", "Zed"))
#>   label frame member method candidates
#> 1 Alder  city      a  alias       <NA>
#> 2     B  city      b  exact       <NA>
#> 3   Zed  <NA>   <NA>   none       <NA>
```

The cities `a` and `b` take the value of their region. The people are
counted in thousands, so the converted column holds thousands of
households.

[`vignette("attributes")`](https://optimal2050.github.io/nestedscales/r/articles/attributes.md)
has the full account.

## Definition files

A scale is stored as a definition: a JSON header with its tables inline,
or a bundle directory with Arrow or CSV tables, which the Python binding
reads as well.
[`write_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
and
[`read_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
exchange them, and
[`scale_catalog()`](https://optimal2050.github.io/nestedscales/r/reference/scale_catalog.md)
lists the definitions installed packages ship:

``` r

path <- file.path(tempdir(), "nace.json")
write_scale(ind, path)
scale_frames(read_scale(path))
#> [1] "section"  "division" "class"
scale_catalog()[c("id", "name", "frames", "n_leaves", "package")]
#> [1] id       name     frames   n_leaves package 
#> <0 rows> (or 0-length row.names)
```

## Several dimensions

[`scale_product()`](https://optimal2050.github.io/nestedscales/r/reference/scale_product.md)
combines scales into one multi-dimensional index without materialising
the product of their leaves.
[`recast_product()`](https://optimal2050.github.io/nestedscales/r/reference/recast_product.md),
[`join_product()`](https://optimal2050.github.io/nestedscales/r/reference/join_product.md)
and
[`filter_product()`](https://optimal2050.github.io/nestedscales/r/reference/filter_product.md)
apply the single-scale operations axis by axis.

``` r

p <- scale_product(a = scale_example(), b = scale_example2())
product_size(p)
#> $axes
#> a b 
#> 7 4 
#> 
#> $total
#> [1] 28
```

## Further operations

- [`cluster_scale()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_scale.md)
  groups members by their data and returns the scale with the clusters
  as a new frame.
- [`reconcile_scale()`](https://optimal2050.github.io/nestedscales/r/reference/reconcile_scale.md)
  compares aggregated data with an independent total.
- [`as_scale_array()`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_array.md)
  converts long data to a dense array over a scale, and
  [`write_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale_dataset.md)
  stores data as an Arrow dataset together with its scales.

All operations accept a `data.frame`, tibble, `data.table`, dtplyr table
or arrow dataset and return the same class; lazy inputs return a query
unless `collect = TRUE`.
