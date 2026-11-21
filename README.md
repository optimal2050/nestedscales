
<!-- README.md is generated from README.Rmd. Please edit that file -->

# nestedscales

<!-- badges: start -->

[![CRAN
status](https://www.r-pkg.org/badges/version/nestedscales)](https://CRAN.R-project.org/package=nestedscales)
[![CRAN
downloads](https://cranlogs.r-pkg.org/badges/grand-total/nestedscales)](https://cran.r-project.org/package=nestedscales)
<!-- badges: end -->

nestedscales represents a discrete data dimension at multiple
resolutions and recasts tabular data between them. A **nested scale**
stores one row per finest-grained member, or *leaf*, and one column for
each coarser grouping, or *frame*. Each frame assigns leaves to members;
frames may form a hierarchy or cross-cut one another, including
product-like overlays. All mappings are derived from membership at the
leaf level.

## The structure

Three levels over five leaves, drawn as a tree and as the table a nested
scale stores:

    group     subgroup     item            group  subgroup  item  kind
                                           -----  --------  ----  ----
    G1 ──┬── G1a ──┬── i1                  G1     G1a       i1    x
         │         └── i2                  G1     G1a       i2    y
         └── G1b ───── i3                  G1     G1b       i3    x
    G2 ───── G2a ──┬── i4                  G2     G2a       i4    y
                   └── i5                  G2     G2a       i5    y

Each row is a leaf and each column a frame. `group`, `subgroup` and
`item` nest in one another; `kind` groups the same leaves another way
and nests in none of them. Data keyed by any frame can be moved to any
other, because both are groupings of the same leaves.

``` r
library(nestedscales)

s <- scale_from_leaftable(
  data.frame(
    group    = c("G1", "G1", "G1", "G2", "G2"),
    subgroup = c("G1a", "G1a", "G1b", "G2a", "G2a"),
    kind     = c("x", "y", "x", "y", "y"),
    item     = c("i1", "i2", "i3", "i4", "i5")
  ),
  frames = c("group", "subgroup", "kind", "item"), name = "generic"
)
scale_nests(s, "group", "subgroup")
#> [1] TRUE
scale_nests(s, "subgroup", "kind")
#> [1] FALSE
#> attr(,"offenders")
#> [1] "x" "y"
scale_children(s, "group", "G1")
#> [1] "G1a" "G1b"
scale_members(s, "kind")
#> [1] "x" "y"
```

The package defines:

- **Structure**: the levels of a scale, the members at each level, and
  the relations between levels (nested, crossed, uniform).
- **Transition rules** between levels, chosen per value column and aware
  of direction: `sum`, `weighted_mean`, `mean`, and `copy`; `sd` for
  aggregation; and `share` or `logshare` for within-parent shares.
- **Operations**: converting data between levels, attaching level labels
  to a dataset, subsetting, combining several scales into one
  multi-dimensional index, clustering members into new levels, and
  storing data together with its scales.
- **Labels, attributes and definitions**: display names for members and
  levels, in named variants; values that belong to a member but are not
  weights (a calorific value, an emission factor), resolved along the
  hierarchy and applied row by row; alternative spellings matched
  strictly; and language-neutral definition files, with a catalogue of
  the ones installed packages ship.
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
from a table. `vignette("nestedscales")` introduces the functions; the
[package website](https://optimal2050.github.io/nestedscales/) includes
a roadmap of what is available and what is planned.

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

Declare the levels, coarsest first:

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

## Moving data between levels

Data keyed at one level is recast to another with a rule per value
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

## Definition files and attributes

Scales travel as definition files (a JSON header with the tables inline,
or a bundle with Arrow or CSV tables) that the Python binding reads as
well. A scale may also carry values that belong to its members, such as
a calorific value per fuel; the two below are illustrative.

``` r
fuels <- scale_from_leaftable(
  data.frame(carrier = c("Coal", "Coal", "Gas"),
             fuel = c("Anthracite", "Lignite", "NaturalGas")),
  frames = c("carrier", "fuel"), leaf = "fuel", name = "fuels",
  attributes = data.frame(
    frame = "fuel", member = c("Anthracite", "NaturalGas"), attribute = "lhv",
    kind = "property", value = c(28, 50), unit_of_measure = "GJ/t",
    source = "example"
  ),
  aliases = data.frame(frame = "fuel", member = "NaturalGas", alias = "NG",
                       source = "example")
)
file <- tempfile(fileext = ".json")
write_scale(fuels, file)
fuels <- read_scale(file)
fuels
#> NestedScale: fuels
#> Frames (2, coarsest first):
#>   - carrier (2)
#>     - fuel (3)
#> Leaves: 3
#> Attributes: lhv (sources: example) -- 2 at fuel
#> Aliases: 1 (example)

fuel_use <- data.frame(fuel = c("Anthracite", "NaturalGas"), t = c(100, 100))
convert_scale(fuel_use, fuels, "lhv", from_unit = "t", to_unit = "GJ")
#>         fuel    t lhv lhv.origin_frame
#> 1 Anthracite 2800  28             fuel
#> 2 NaturalGas 5000  50             fuel

scale_match(fuels, c("NG", "lignite", "Peat"))
#>     label frame     member method candidates
#> 1      NG  fuel NaturalGas  alias       <NA>
#> 2 lignite  fuel    Lignite  exact       <NA>
#> 3    Peat  <NA>       <NA>   none       <NA>
```

`scale_attributes()` resolves a value for every member of a frame,
walking to the nearest coarser level that holds one; `scale_match()`
resolves names and model codes through the alias table, strictly.

## Design

- **A scale is a definition, not a container.** It holds the leaves, the
  frames that group them and the weights that size them. Data stays in
  ordinary tables and is matched to a scale by its codes; the
  experimental `bind_scale()` can also record on the code columns which
  scale and frame they are on.
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
  across a fixed aggregation tree; `reconcile_scale()` here compares
  data aggregated with `sum` or `weighted_mean` against independent
  totals and can balance discrepancies.

## License

Apache License 2.0.
