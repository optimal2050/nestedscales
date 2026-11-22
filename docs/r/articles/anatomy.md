# The NestedScale object

This vignette takes one object apart. The example is a small
classification of industries by business code, in the style of a
statistical classification of activities: sections (`C`, Manufacturing)
hold divisions (`C10`, Food products), which hold classes (`C101`). The
codes, the names and every number are invented for illustration and
reproduce no official classification. The example has every awkward
feature: a code reused at two frames, a frame that cross-cuts another, a
leaf with no code at one frame, and attributes stored at three different
frames.

The cross-cutting frame is `size`, a grouping of the classes by the
typical size of their firms, `small` or `large`. Public administration
(`O84`) is not made of firms and has no size, and it is not subdivided,
so its only class carries the code of its division.

``` r

lt <- data.frame(
  section  = c("C", "C", "C", "C", "C", "D", "D", "D", "O"),
  size     = c("small", "large", "small", "large", "large",
               "large", "small", "small", NA),
  division = c("C10", "C10", "C11", "C24", "C24",
               "D35", "D35", "D35", "O84"),
  class    = c("C101", "C102", "C110", "C241", "C242",
               "D351", "D352", "D353", "O84")
)
at <- data.frame(
  frame     = c("class", "class", "division", "section", "class", "division"),
  member    = c("C101", "C102", "D35", "C", "C241", "D35"),
  attribute = c("wage", "wage", "wage", "wage", "floor_area", "floor_area"),
  kind      = c(rep("property", 4), "factor", "factor"),
  value     = c(30, 28, 45, 32, 60, 20),
  unit_of_measure = c(rep("thousand/employee", 4), "m2/employee",
                      "m2/employee"),
  source    = "example"
)
al <- data.frame(
  frame  = c("class", "division", "class", "division", "division"),
  member = c("C101", "C10", "O84", "O84", "O84"),
  alias  = c("meat", "food", "public admin", "public admin", "government"),
  source = "example"
)
x <- scale_from_leaftable(
  lt, frames = c("section", "size", "division", "class"), leaf = "class",
  attributes = at, aliases = al, name = "industries"
)
x
#> NestedScale: industries
#> Frames (4, coarsest first):
#>   - section (3)
#>     - size (2)  [1 member unassigned]
#>       - division (5)
#>         - class (9)
#> Leaves: 9
#> Attributes: wage, floor_area (sources: example) -- 1 at section, 2 at division, 3 at class
#> Aliases: 5 (example)
```

## The object

A `NestedScale` is an S7 object with eight properties.
[`str()`](https://rdrr.io/r/utils/str.html) lists them with their size
and purpose:

``` r

str(x)
#> <NestedScale> industries@92678be1
#> ├─ leaftable    data.frame [9 x 4]            one row per leaf
#> │  ├─ class     leaf column          fixed
#> │  ├─ section   frame                fixed
#> │  ├─ size      frame                fixed
#> │  └─ division  frame                fixed
#> ├─ frames       chr [4]              fixed    section, size, division, class
#> ├─ members      list [4]             derived  from leaftable: section 3, size 2, division 5, class 9
#> ├─ leaf         chr [1]              fixed    class
#> ├─ meta         list [4]             mutable  name, desc, weights, default_weight
#> ├─ attributes   data.frame [6 x 10]  mutable  attach_attributes_scale()
#> ├─ aliases      data.frame [5 x 4]   mutable  attach_aliases_scale()
#> └─ labels       data.frame [0 x 4]   mutable  attach_labels_scale()
```

The standard S7 tools apply: `S7::prop_names(x)` gives the names,
`x@frames` or `S7::prop(x, "frames")` reads one property, and
`S7::props(x)` returns all of them as a list.

``` r

S7::prop_names(x)
#> [1] "leaftable"  "frames"     "members"    "leaf"       "meta"      
#> [6] "attributes" "aliases"    "labels"
x@frames
#> [1] "section"  "size"     "division" "class"
```

The object is a **definition**: the leaves, the frames that group them,
and the weights that say how big each leaf is. It never holds data. Data
stays in ordinary tables, and a table is tied to a scale by its code
columns; see [The data link](#the-data-link) below.

| property | type | holds |
|----|----|----|
| `leaftable` | `data.frame` | one row per leaf: one column per frame, the leaf column, weight columns |
| `frames` | `character` | the hierarchy, ordered coarsest first |
| `members` | named `list` | the ordered code vocabulary at each frame |
| `leaf` | `character` | the name of the leaf column (`"leaf"` by default) |
| `meta` | `list` | `name`, `desc`, `weights`, `default_weight`, and whatever the builder adds |
| `attributes` | `data.frame` | values keyed by `(frame, member)`: `attribute`, `kind`, `value`, `lower`, `upper`, `unit_of_measure`, `source`, `note` |
| `aliases` | `data.frame` | alternative spellings keyed by `(frame, member)`: `alias`, `source` |
| `labels` | `data.frame` | display names keyed by `(frame, member, variant)`: `label` |

Everything else – parent/child tables, ancestry, shares, resolved
attributes – is derived on demand; nothing is cached on the object. The
three tables are empty unless the builder fills them; a scale saved by
an earlier version, which had no such properties, loads and validates
unchanged.

## The leaftable

``` r

scale_leaftable(x)
#>   section  size division class
#> 1       C small      C10  C101
#> 2       C large      C10  C102
#> 3       C small      C11  C110
#> 4       C large      C24  C241
#> 5       C large      C24  C242
#> 6       D large      D35  D351
#> 7       D small      D35  D352
#> 8       D small      D35  D353
#> 9       O  <NA>      O84   O84
```

Each row is one leaf. The leaf column (`class` here) is unique and
complete. Frame columns may hold `NA`: `O84` has no firm size, so it
does not participate at the `size` frame, and `na_action=` decides what
recasts do about it. The leaf column may be the finest frame, as here:
the frame column *is* the leaf column.

## Frames, members, ranks

``` r

scale_frames(x)
#> [1] "section"  "size"     "division" "class"
scale_leaf_frame(x)                # the finest frame, or the leaf column
#> [1] "class"
scale_members(x, "division")       # the members at one frame
#> [1] "C10" "C11" "C24" "D35" "O84"
scale_members(x)                   # the leaves
#> [1] "C101" "C102" "C110" "C241" "C242" "D351" "D352" "D353" "O84"
scale_rank(x, "division")
#> [1] 3
```

Codes are **not unique across frames**: `O84` is a division and a class
here. Every function that takes a code therefore takes its frame as
well.

Navigation is derived from the leaftable and routed through the leaves,
so a frame that cross-cuts another reports overlap rather than invented
containment:

``` r

scale_nests(x, "division", "class")  # a tree
#> [1] TRUE
scale_nests(x, "size", "division")   # C10 and D35 are small and large
#> [1] FALSE
#> attr(,"offenders")
#> [1] "C10" "D35"
scale_parents(x, "division", "D35", target = "size")
#> [1] "small" "large"
scale_ancestors(x, "class", "D352")
#>      frame member
#> 1  section      D
#> 2     size  small
#> 3 division    D35
scale_descendants(x, "section", "C")
#>       frame member
#> 1      size  small
#> 2      size  large
#> 3  division    C10
#> 4  division    C11
#> 5  division    C24
#> 6     class   C101
#> 7     class   C102
#> 8     class   C110
#> 9     class   C241
#> 10    class   C242
head(scale_ancestry(x), 4)
#>   parent_frame parent child_frame child
#> 1      section      C        size large
#> 2      section      C        size small
#> 3      section      C    division   C10
#> 4      section      C    division   C11
```

## The attribute table

Attributes live in one long table, and a row may sit on **any** member,
not only on a leaf. Here a wage per employee is given for two classes,
one division and one section, and a floor area per employee for one
class and one division:

``` r

scale_attributes(x)
#>      frame member  attribute     kind value lower upper   unit_of_measure
#> 1    class   C101       wage property    30    NA    NA thousand/employee
#> 2    class   C102       wage property    28    NA    NA thousand/employee
#> 3 division    D35       wage property    45    NA    NA thousand/employee
#> 4  section      C       wage property    32    NA    NA thousand/employee
#> 5    class   C241 floor_area   factor    60    NA    NA       m2/employee
#> 6 division    D35 floor_area   factor    20    NA    NA       m2/employee
#>    source note
#> 1 example <NA>
#> 2 example <NA>
#> 3 example <NA>
#> 4 example <NA>
#> 5 example <NA>
#> 6 example <NA>
```

Reading with a `frame` resolves one value per member, walking to the
nearest coarser frame when a member has none of its own, and says where
the value came from:

``` r

scale_attributes(x, "wage", frame = "class")[
  c("member", "value", "unit_of_measure", "origin_frame", "origin_member")]
#>   member value   unit_of_measure origin_frame origin_member
#> 1   C101    30 thousand/employee        class          C101
#> 2   C102    28 thousand/employee        class          C102
#> 3   C110    32 thousand/employee      section             C
#> 4   C241    32 thousand/employee      section             C
#> 5   C242    32 thousand/employee      section             C
#> 6   D351    45 thousand/employee     division           D35
#> 7   D352    45 thousand/employee     division           D35
#> 8   D353    45 thousand/employee     division           D35
#> 9    O84    NA              <NA>         <NA>          <NA>
```

Attributes are **not weights**. A weight says how big a leaf is and
drives aggregation; an attribute is a per-member conversion factor and
is consumed only by
[`convert_scale()`](https://optimal2050.github.io/nestedscales/r/reference/convert_scale.md).
The constructor promotes numeric leaftable columns to weights, so a wage
must be passed as `attributes=`, never as a leaftable column. Every
attribute name carries a `kind`: `property` (an invertible ratio) or
`factor` (one-way).

``` r

SCALE_ATTRIBUTE_KINDS
#> [1] "property" "factor"
```

[`vignette("attributes")`](https://optimal2050.github.io/nestedscales/r/articles/attributes.md)
has the reasoning and the full account of inheritance, sources and
conversion.

## The alias table

The members of this scale are codes; the alias table holds the names and
spellings by which other tables refer to the same activities.

``` r

scale_aliases(x)
#>      frame member        alias  source
#> 1    class   C101         meat example
#> 2 division    C10         food example
#> 3    class    O84 public admin example
#> 4 division    O84 public admin example
#> 5 division    O84   government example
scale_match(x, c("meat", "Public Admin", "C242"))
#>          label frame member    method              candidates
#> 1         meat class   C101     alias                    <NA>
#> 2 Public Admin  <NA>   <NA> ambiguous class/O84; division/O84
#> 3         C242 class   C242     exact                    <NA>
```

One alias may point at several members (`public admin` above); matching
reports that as ambiguous unless `frame=` narrows it. Matching is exact
and case-insensitive, with no fuzzy stage.

## The label table

Labels are display names. A label belongs to a member and to a named
*variant*, so one member may carry a full name, a short one and a
translation, while another frame carries none at all and is shown by its
codes. A row with `member = NA` names the frame itself. The divisions
get two variants here, a short name and a long one, and the short one is
declared the default:

``` r

x <- attach_labels_scale(
  x,
  data.frame(
    frame   = "division",
    member  = rep(c("C10", "C24", "O84", NA), 2),
    variant = rep(c("short", "long"), each = 4),
    label   = c("Food", "Metals", "Administration", "Division",
                "Manufacture of food products",
                "Manufacture of basic metals",
                "Public administration", "Division of activity")
  ),
  default = "short"
)
scale_labels(x)
#>      frame member variant                        label
#> 1 division    C10   short                         Food
#> 2 division    C24   short                       Metals
#> 3 division    O84   short               Administration
#> 4 division   <NA>   short                     Division
#> 5 division    C10    long Manufacture of food products
#> 6 division    C24    long  Manufacture of basic metals
#> 7 division    O84    long        Public administration
#> 8 division   <NA>    long         Division of activity
scale_label(x, c("C10", "C11", "O84"), frame = "division")
#> [1] "Food"           "C11"            "Administration"
scale_label(x, c("C10", "C11", "O84"), frame = "division", variant = "long")
#> [1] "Manufacture of food products" "C11"                         
#> [3] "Public administration"
scale_label(x, scale_members(x, "size"), frame = "size")   # no labels: codes
#> [1] "small" "large"
```

`C11` has no label in either variant and is shown by its code. Aliases
and labels serve different purposes. An alias is a spelling to be
*recognised*
([`scale_match()`](https://optimal2050.github.io/nestedscales/r/reference/scale_match.md));
a label is a name to be *shown*
([`scale_label()`](https://optimal2050.github.io/nestedscales/r/reference/scale_label.md),
`join_scale(labels = )`).

## Weights and meta

``` r

scale_weights(x)                        # none declared here
#> character(0)
S7::prop(x, "meta")[c("name", "desc")]
#> $name
#> [1] "industries"
#> 
#> $desc
#> [1] ""
```

`meta$name` is load-bearing:
[`join_scale()`](https://optimal2050.github.io/nestedscales/r/reference/join_scale.md)
prefixes the columns it attaches with `"<name>."`,
[`scale_map_between()`](https://optimal2050.github.io/nestedscales/r/reference/scale_map_between.md)
names its label columns after the objects, and
[`write_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
needs a name for the definition. Further fields passed to the
constructor are kept in `meta` as given.

## The data link

A table of data is tied to a scale by its code columns. Unbound, the tie
is the column name alone: a column called `division` is read as codes at
the `division` frame. Two scales can share frame names and codes, so the
name does not say *which* scale the data is on.
[`bind_scale()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md)
records it on the column itself, together with the scale’s identity. The
link is experimental: it is lost when the column is converted to a
factor or a plain character vector, and it may change.

``` r

scale_id(x)
#> [1] "industries@92678be1"
d <- data.frame(class = scale_members(x), jobs = seq_along(scale_members(x)))
b <- bind_scale(d, x)
scale_link(b)
#>   column      scale frame                  id
#> 1  class industries class industries@92678be1
```

[`scale_id()`](https://optimal2050.github.io/nestedscales/r/reference/scale_id.md)
is the scale’s name plus a hash of its structure – leaf column, frames
and memberships. Weights, attributes, aliases and labels do not enter,
so enriching a scale does not detach the data bound to it; a subset or a
re-grouping is a different scale.

A bound column is still a character vector. It keeps the link through
row subsetting, `mutate()`, grouping, joins and row binding, and the
verbs use it: the source frame is taken from the link, the result is
bound to the target frame, and data bound to another scale is refused.

``` r

register_scale_rule("jobs", "sum")
out <- recast_scale(b, x, target = "division")
scale_link(out)
#>     column      scale    frame                  id
#> 1 division industries division industries@92678be1
clear_scale_rules("jobs")
```

Unbound data behaves as before, and its results stay unbound. A lazy
table (arrow, dtplyr) cannot carry the link in memory;
[`write_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale_dataset.md)
records it in the store and
[`scale_link()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md)
reads it back.

## What the validator guarantees

[`scale_from_leaftable()`](https://optimal2050.github.io/nestedscales/r/reference/scale_from_leaftable.md)
and every operation that rebuilds a scale enforce:

- the leaf column is present, unique and complete; every frame is a
  leaftable column and `members` are exactly its non-`NA` values, in a
  stable order;
- weights are numeric and finite;
- every attribute and alias row names a `(frame, member)` that is a
  member; `value` is finite; `lower <= value <= upper` where given;
  `kind` is one of `SCALE_ATTRIBUTE_KINDS` and one attribute name has
  one kind; `unit_of_measure` and `source` are non-empty; no duplicate
  `(frame, member, attribute, source)` rows and no duplicate alias rows.

The order of `frames` is a convention, coarsest first; the
direction-dependent rules (`share`, residuals, reconciliation) follow
it.

Subsetting keeps the tables consistent:
[`filter_scale()`](https://optimal2050.github.io/nestedscales/r/reference/filter_scale.md)
and `[` keep the attribute and alias rows of every surviving member at
every frame, and
[`prune_scale()`](https://optimal2050.github.io/nestedscales/r/reference/prune_scale.md)
keeps the rows at the frames that survive the collapse.

``` r

manufacturing <- x["section", "C"]
scale_attributes(manufacturing)[c("frame", "member", "attribute", "value")]
#>     frame member  attribute value
#> 1   class   C101       wage    30
#> 2   class   C102       wage    28
#> 3 section      C       wage    32
#> 4   class   C241 floor_area    60
```

[`prune_scale()`](https://optimal2050.github.io/nestedscales/r/reference/prune_scale.md)
needs the frames above the new leaf frame to nest, so the cross-cutting
`size` has to go first:

``` r

tree <- scale_from_leaftable(
  lt[c("section", "division", "class")],
  frames = c("section", "division", "class"),
  leaf = "class", attributes = at, aliases = al, name = "tree"
)
scale_aliases(prune_scale(tree, "division"))
#>      frame member        alias  source
#> 1 division    C10         food example
#> 2 division    O84 public admin example
#> 3 division    O84   government example
```

## Definition files

A scale is stored as a definition, not as an R object: a JSON header
with the three tables inline, or, for large scales, a `<name>.scale/`
bundle directory holding the header and the tables as Arrow IPC or CSV
files. The Python binding reads and writes the same files.

``` r

path <- file.path(tempdir(), "industries.json")
write_scale(x, path)
cat(head(readLines(path), 12), sep = "\n")
#> {
#>   "schema_version": 2,
#>   "nestedscales": "0.3.0",
#>   "class": "nestedscales::NestedScale",
#>   "name": "industries",
#>   "leaf": "class",
#>   "frames": ["section", "size", "division", "class"],
#>   "members": {
#>     "section": ["C", "D", "O"],
#>     "size": ["small", "large"],
#>     "division": ["C10", "C11", "C24", "D35", "O84"],
#>     "class": ["C101", "C102", "C110", "C241", "C242", "D351", "D352", "D353", "O84"]
back <- read_scale(path)
identical(scale_frames(back), scale_frames(x))
#> [1] TRUE
identical(scale_attributes(back), scale_attributes(x))
#> [1] TRUE
```

`write_scale(format = "yaml")` writes the same header as YAML, and
[`read_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
accepts either. Installed packages register directories of definitions;
[`scale_catalog()`](https://optimal2050.github.io/nestedscales/r/reference/scale_catalog.md)
lists them and `read_scale(id)` opens one by its id:

``` r

scale_catalog()[c("id", "name", "kind", "frames", "n_leaves", "package")]
#> [1] id       name     kind     frames   n_leaves package 
#> <0 rows> (or 0-length row.names)
```

## The registry

One package-level registry changes behaviour explicitly. **Rules** map
value-column names to their aggregation rule; there is no fallback, and
an unregistered column without `rule=` is an error:

``` r

SCALE_RULES
#> [1] "sum"           "weighted_mean" "mean"          "copy"         
#> [5] "sd"            "share"         "logshare"
register_scale_rule("jobs", "sum")
register_scale_rule("wage", "weighted_mean", weight = "jobs")
get_scale_rule("wage")
#> $rule
#> [1] "weighted_mean"
#> 
#> $weight
#> [1] "jobs"
#> 
#> $scope
#> NULL
list_scale_rules()
#>   param          rule weight scope
#> 1  jobs           sum   <NA>  <NA>
#> 2  wage weighted_mean   jobs  <NA>
clear_scale_rules()
```

A rule may be scoped to one dimension with `scope=`, so a `jobs` column
aggregates the same way over industries, regions and months without
being registered three times – or differently, when it should.

## Where to next?

- [`vignette("nestedscales")`](https://optimal2050.github.io/nestedscales/r/articles/nestedscales.md)
  – the tour of the main functions.
- [`vignette("attributes")`](https://optimal2050.github.io/nestedscales/r/articles/attributes.md)
  – attributes, aliases and conversion on a small scale of cities.
