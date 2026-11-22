# Roadmap

nestedscales is the core package of a family for multi-level discrete
representations of data, used in modelling, data processing and
visualization. This page lists what the core provides in the current
release, what the dimension packages add, and what is planned. It is
updated with each release.

## Scope

A **nested scale** represents one dimension of a dataset or model as a
table of leaves, the finest members, with one column per coarser level,
the frames. Every frame nests in the leaves. Frames may nest in each
other (a tree: activity in division in section) or overlay each other
(hours of the day and months of the year); every operation routes
through the leaves, so both are handled alike.

The package covers three things:

1.  **Structure**: the levels, the members at each level, and which
    pairs of levels nest, cross or are uniform.
2.  **Transition rules**: how a value moves between levels – summed,
    averaged, weighted, copied, or expressed as a share of its parent.
3.  **Operations**: converting data, attaching labels, subsetting,
    combining dimensions, grouping members into new levels, and storing
    data with its scales.

## Available now (0.3.0)

The core is the structure, the transition rules, conversion and joining.
Five features are marked experimental and may change or be removed:
attributes with
[`convert_scale()`](https://optimal2050.github.io/nestedscales/r/reference/convert_scale.md),
products of scales, arrays and stored datasets, distances, and
[`reconcile_scale()`](https://optimal2050.github.io/nestedscales/r/reference/reconcile_scale.md).
The data link is experimental as well.

### Structure

- [`scale_from_leaftable()`](https://optimal2050.github.io/nestedscales/r/reference/scale_from_leaftable.md)
  builds a scale from a table;
  [`scale_frames()`](https://optimal2050.github.io/nestedscales/r/reference/scale_frames.md),
  [`scale_members()`](https://optimal2050.github.io/nestedscales/r/reference/scale_members.md),
  [`scale_leaf_column()`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaf_column.md),
  [`scale_leaftable()`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaftable.md),
  [`scale_weights()`](https://optimal2050.github.io/nestedscales/r/reference/scale_weights.md),
  [`scale_rank()`](https://optimal2050.github.io/nestedscales/r/reference/scale_rank.md)
  and
  [`scale_leaf_frame()`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaf_frame.md)
  read it.
- Relations between levels:
  [`scale_nests()`](https://optimal2050.github.io/nestedscales/r/reference/scale_nests.md),
  [`scale_crosses()`](https://optimal2050.github.io/nestedscales/r/reference/scale_crosses.md),
  [`scale_is_uniform()`](https://optimal2050.github.io/nestedscales/r/reference/scale_is_uniform.md);
  [`scale_family()`](https://optimal2050.github.io/nestedscales/r/reference/scale_family.md)
  and
  [`scale_ancestry()`](https://optimal2050.github.io/nestedscales/r/reference/scale_ancestry.md)
  list parent-child pairs;
  [`scale_children()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md),
  [`scale_parents()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md),
  [`scale_descendants()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md)
  and
  [`scale_ancestors()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md)
  navigate.
- [`scale_share()`](https://optimal2050.github.io/nestedscales/r/reference/scale_share.md)
  and
  [`scale_coverage()`](https://optimal2050.github.io/nestedscales/r/reference/scale_coverage.md)
  report weights and what fraction of a parent a subset keeps.
- Partial membership (`NA` at a level) and declared residual members
  ([`scale_residuals()`](https://optimal2050.github.io/nestedscales/r/reference/scale_residuals.md))
  are part of the representation.
- [`filter_scale()`](https://optimal2050.github.io/nestedscales/r/reference/filter_scale.md)
  and
  [`prune_scale()`](https://optimal2050.github.io/nestedscales/r/reference/prune_scale.md)
  subset and collapse a scale, keeping the record of coverage.
- [`scale_id()`](https://optimal2050.github.io/nestedscales/r/reference/scale_id.md)
  gives the identity of a scale, its name and a hash of its structure.
  [`scale_tree()`](https://optimal2050.github.io/nestedscales/r/reference/scale_tree.md),
  also printed by [`str()`](https://rdrr.io/r/utils/str.html), lists the
  parts of a scale and marks each one as fixed (part of the identity),
  derived or mutable.
- The classes `NestedScale` and `ScaleProduct` are exported and
  documented.

### Transition rules

- Seven rules, `SCALE_RULES`: `sum`, `weighted_mean`, `mean`, `copy`,
  `sd`, `share`, `logshare`. Each is defined in both directions, so
  aggregation and disaggregation are one operation.
- Weights are named columns of the scale; several can coexist and each
  value column may use its own.
- [`register_scale_rule()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_rule.md)
  records the rule for a named value column, scoped per dimension, so a
  model’s parameters recast without repeating the rule.
- Declared residuals aggregate upward but are never allocated to when a
  coarse value is split.

### Operations

- [`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md)
  converts data between any two levels of a scale, or to the leaves of
  another scale that shares leaf codes;
  [`recast_to_leaves()`](https://optimal2050.github.io/nestedscales/r/reference/recast_to_leaves.md)
  and
  [`recast_from_leaves()`](https://optimal2050.github.io/nestedscales/r/reference/recast_to_leaves.md)
  are its two halves;
  [`recast_crosswalk()`](https://optimal2050.github.io/nestedscales/r/reference/recast_crosswalk.md)
  runs the same engine over a correspondence built elsewhere.
- [`scale_map()`](https://optimal2050.github.io/nestedscales/r/reference/scale_map.md)
  and
  [`scale_map_between()`](https://optimal2050.github.io/nestedscales/r/reference/scale_map_between.md)
  expose the crosswalks;
  [`register_scale_map()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_map.md)
  installs exact or hand-audited ones.
- [`join_scale()`](https://optimal2050.github.io/nestedscales/r/reference/join_scale.md)
  attaches labels, coarser levels, shares and weights to a dataset.
- The data link (experimental):
  [`bind_scale()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md)
  records on the code columns of a table which scale and level they are
  on, and
  [`scale_link()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md)
  reports it. The link survives subsetting, joins and row binding; the
  conversion functions read the source level from it, stop when the data
  is bound to another scale, and bind their result.
- [`reconcile_scale()`](https://optimal2050.github.io/nestedscales/r/reference/reconcile_scale.md)
  compares aggregated data with an independent total and can balance the
  gap.
- [`scale_product()`](https://optimal2050.github.io/nestedscales/r/reference/scale_product.md)
  combines several scales into one multi-dimensional index;
  [`recast_product()`](https://optimal2050.github.io/nestedscales/r/reference/recast_product.md),
  [`join_product()`](https://optimal2050.github.io/nestedscales/r/reference/join_product.md)
  and
  [`filter_product()`](https://optimal2050.github.io/nestedscales/r/reference/filter_product.md)
  work over it without materialising the product of leaves.
- [`cluster_scale()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_scale.md),
  [`cluster_contiguous()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_contiguous.md),
  [`cluster_medoids()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_medoids.md)
  and
  [`cluster_sweep()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_sweep.md)
  group members by their data and return the scale with the clusters as
  a new level.
- [`as_scale_array()`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_array.md)
  and
  [`as_scale_table()`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_array.md)
  move between long tables and dense arrays;
  [`write_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale_dataset.md)
  and
  [`open_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/open_scale_dataset.md)
  store data as a partitioned Arrow dataset together with its scales.
- Every operation accepts a `data.frame`, tibble, `data.table`, dtplyr
  table or arrow dataset and returns the same class; lazy inputs return
  a query.

### Labels, attributes, aliases and definitions

- **Labels** are display names keyed by `(frame, member, variant)`: a
  member may have several named variants, a level may have none, and a
  level itself can be named.
  [`attach_labels_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_labels_scale.md)
  adds them,
  [`scale_labels()`](https://optimal2050.github.io/nestedscales/r/reference/scale_labels.md)
  and
  [`scale_label()`](https://optimal2050.github.io/nestedscales/r/reference/scale_label.md)
  read them, and `join_scale(labels = )` attaches them to a dataset.
- A scale may carry **attributes**, physical values keyed by
  `(frame, member)` at any level (a calorific value on a fuel, on its
  carrier or on its group), each with a `kind`, bounds, unit of measure
  and source.
  [`scale_attributes()`](https://optimal2050.github.io/nestedscales/r/reference/scale_attributes.md)
  resolves one value per member along the hierarchy and says where it
  came from;
  [`convert_scale()`](https://optimal2050.github.io/nestedscales/r/reference/convert_scale.md)
  converts a table row by row with it. Attributes are never weights and
  are never recast.
- **Aliases** are alternative labels per member;
  [`scale_match()`](https://optimal2050.github.io/nestedscales/r/reference/scale_match.md)
  resolves labels exactly, case-insensitively, and reports ambiguity.
- **Definition files.**
  [`write_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
  and
  [`read_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
  exchange a scale as a JSON header with inline tables, or a bundle with
  Arrow or CSV tables; YAML is accepted. The Python binding reads the
  same files, except the label table.
  [`scale_catalog()`](https://optimal2050.github.io/nestedscales/r/reference/scale_catalog.md)
  lists the definitions installed packages ship, and
  [`read_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
  opens one by its id.

### Dimension packages

- [timescales](https://github.com/optimal2050/timescales): `Calendar`, a
  nested scale of time. A catalog of standard calendars, construction
  from tokens, conversion from datetimes, sampled and fiscal calendars,
  calendar plots.
- [geoscales](https://github.com/optimal2050/geoscales): `GeoScale`, a
  nested scale of space. Region hierarchies from data providers,
  geometry and area weights, maps.
- The *Building a dimension package* section of the reference lists the
  hooks a subclass fills, including how it stores and restores its
  payload in a definition file.

Both are designed for optimization and simulation models, where the
labelled time slices and regions become the index sets of variables and
constraints (see [energyRt](https://github.com/optimal2050/energyRt)).

## Planned

The order is not fixed; items move up as the modelling packages need
them.

- **User-defined transition rules.** Today a rule is one of the seven
  names. A registered rule will also be able to be a function of the
  values and weights in a group, so a dimension or a model can define
  its own aggregation (a maximum, a quantile, a nonlinear combination).
- **Joint weights on products.** `ScaleProduct` reserves `joint_weights`
  for a weight that varies across axes together (an hourly profile that
  differs by region). The slot is validated but not yet used by
  [`recast_product()`](https://optimal2050.github.io/nestedscales/r/reference/recast_product.md).
- **Residual protection across scales.** Declared residuals are
  protected when disaggregating within one scale; the cross-scale route
  does not yet apply it.
- **Visualization in the core.** Plots live in the dimension packages
  (calendar heat maps, choropleths). A dimension-free layout of a
  scale’s structure – icicle and stacked views of levels and shares –
  belongs in the core, so any dimension can be drawn and the dimension
  packages can build on it.
- **Scales from continuous variables.** Income brackets, temperature
  regimes and vintage bins are nested scales whose leaves are intervals
  of a continuous variable. Today they are binned by hand before
  [`scale_from_leaftable()`](https://optimal2050.github.io/nestedscales/r/reference/scale_from_leaftable.md);
  a constructor taking breakpoints, with the interval bounds kept as
  weights, would build them directly.
- **Shipped definitions.** The core ships none. Classifications (fuels,
  NACE, ISIC, technology vintages) belong to the packages that maintain
  them, as definition files those packages register in the catalogue.
- **Regional attribute values.** A national calorific value is the same
  attribute on the same member in another region. It belongs to a
  product of the scale with a `GeoScale`, attached under its own source;
  not built yet.
- **Labels in the Python binding.** The binding reads and writes
  definition files but does not yet carry the label table.
- **Declared content of a definition file.** A file does not yet state
  which optional tables it holds, so an older reader cannot tell that it
  is skipping one; a step of the schema version will record it.

## Not planned

- Trees as node objects, or an object per member. The flat leaf table is
  the representation, and it is what keeps conversion the same for every
  dimension.
- Guessing a rule when none is given. A value column with no rule is an
  error; a silently chosen rule is a silent unit error.
