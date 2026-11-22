# Changelog

## nestedscales 0.3.0

### Breaking changes

- New vocabulary, with no deprecated aliases: a *member* is one item of
  a frame (was “unit”), a *leaf* is a member of the finest layer and one
  row of the leaftable (was “atom”), and the *leaf column* is the column
  of the leaftable that identifies the leaves (was “key”). “Unit” now
  means a unit of measure only (`unit_of_measure`, `from_unit`,
  `to_unit`), and `key=` the column of a data table that holds the
  codes.
- Renamed functions: `scale_units()` to
  [`scale_members()`](https://optimal2050.github.io/nestedscales/r/reference/scale_members.md),
  `scale_key()` to
  [`scale_leaf_column()`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaf_column.md),
  `scale_atom_level()` to
  [`scale_leaf_frame()`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaf_frame.md),
  `recast_to_atoms()` and `recast_from_atoms()` to
  [`recast_to_leaves()`](https://optimal2050.github.io/nestedscales/r/reference/recast_to_leaves.md)
  and
  [`recast_from_leaves()`](https://optimal2050.github.io/nestedscales/r/reference/recast_to_leaves.md),
  `product_atoms()` to
  [`product_leaves()`](https://optimal2050.github.io/nestedscales/r/reference/product_leaves.md),
  `scale_atom_pairs()` to
  [`scale_leaf_pairs()`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaf_pairs.md),
  `as_scale_unit()` and `is_scale_unit()` to
  [`as_scale_member()`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_member.md)
  and
  [`is_scale_member()`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_member.md)
  (class `scale_member`). Renamed arguments: `unit` to `member` in
  [`filter_scale()`](https://optimal2050.github.io/nestedscales/r/reference/filter_scale.md),
  [`filter_product()`](https://optimal2050.github.io/nestedscales/r/reference/filter_product.md),
  [`scale_children()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md),
  [`scale_parents()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md),
  [`scale_descendants()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md),
  [`scale_ancestors()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md)
  and
  [`recast_crosswalk()`](https://optimal2050.github.io/nestedscales/r/reference/recast_crosswalk.md);
  `units` to `members` in
  [`scale_label()`](https://optimal2050.github.io/nestedscales/r/reference/scale_label.md);
  `scale_units` to `scale_members` in
  [`scale_distance()`](https://optimal2050.github.io/nestedscales/r/reference/scale_distance.md),
  [`cluster_scale()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_scale.md),
  [`cluster_contiguous()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_contiguous.md)
  and
  [`cluster_sweep()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_sweep.md);
  `key` to `leaf` in
  [`NestedScale()`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  and
  [`scale_from_leaftable()`](https://optimal2050.github.io/nestedscales/r/reference/scale_from_leaftable.md).
  The property `NestedScale@key` is `@leaf`, and
  [`scale_vocab()`](https://optimal2050.github.io/nestedscales/r/reference/scale_vocab.md)
  returns `member`, `members` and `leaves`.
- The label, alias and attribute tables, and the results of
  [`scale_labels()`](https://optimal2050.github.io/nestedscales/r/reference/scale_labels.md),
  [`scale_aliases()`](https://optimal2050.github.io/nestedscales/r/reference/scale_aliases.md),
  [`scale_attributes()`](https://optimal2050.github.io/nestedscales/r/reference/scale_attributes.md),
  [`scale_match()`](https://optimal2050.github.io/nestedscales/r/reference/scale_match.md),
  [`scale_descendants()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md)
  and
  [`scale_ancestors()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md),
  name the code column `member` (was `unit`); `origin_unit` is
  `origin_member`.
  [`scale_catalog()`](https://optimal2050.github.io/nestedscales/r/reference/scale_catalog.md)
  returns `leaf` and `n_leaves` (were `key` and `n_atoms`),
  [`summary()`](https://rdrr.io/r/base/summary.html) returns `n_leaves`
  for a scale and the column `leaves` for a product, and
  [`scale_tree()`](https://optimal2050.github.io/nestedscales/r/reference/scale_tree.md)
  lists the part `leaf` with the kind `leaf column`. Printed output says
  “Leaves” and “member”.
- [`scale_from_leaftable()`](https://optimal2050.github.io/nestedscales/r/reference/scale_from_leaftable.md)
  takes a column called `leaf` as the leaf column when `leaf=` is not
  given, otherwise the finest frame; a column called `unit` is no longer
  picked up. The finest frame of
  [`scale_example()`](https://optimal2050.github.io/nestedscales/r/reference/scale_example.md)
  is `item` (was `unit`), which changes its
  [`scale_id()`](https://optimal2050.github.io/nestedscales/r/reference/scale_id.md).
- Definition files are written with schema version 2: the header field
  `leaf` and the table column `member`. Version 1 files and stores, and
  objects saved by earlier versions, are still read.
- `backend_scan()` and `backend_distinct()` are no longer exported.
- [`write_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
  writes a scale held in `meta` as a reference, its name and
  [`scale_id()`](https://optimal2050.github.io/nestedscales/r/reference/scale_id.md),
  and no longer stops on it.
- Marked experimental, which means they may change or be removed in a
  later version: attributes with
  [`convert_scale()`](https://optimal2050.github.io/nestedscales/r/reference/convert_scale.md),
  products of scales
  ([`scale_product()`](https://optimal2050.github.io/nestedscales/r/reference/scale_product.md),
  [`recast_product()`](https://optimal2050.github.io/nestedscales/r/reference/recast_product.md)
  and the `product_*()` functions), arrays and stored datasets
  ([`as_scale_array()`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_array.md),
  [`write_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale_dataset.md),
  [`open_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/open_scale_dataset.md)),
  distances
  ([`scale_distance()`](https://optimal2050.github.io/nestedscales/r/reference/scale_distance.md)
  and its registry) and
  [`reconcile_scale()`](https://optimal2050.github.io/nestedscales/r/reference/reconcile_scale.md).

### New features

- Labels. A scale carries an optional table of display names keyed by
  `(frame, member, variant)`: a member may have several named variants,
  a frame may have none, and a row with `member = NA` names the frame
  itself.
  [`scale_from_leaftable()`](https://optimal2050.github.io/nestedscales/r/reference/scale_from_leaftable.md)
  takes it as `labels=`;
  [`attach_labels_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_labels_scale.md)
  adds rows and sets the default variant,
  [`scale_labels()`](https://optimal2050.github.io/nestedscales/r/reference/scale_labels.md)
  reads the table and
  [`scale_label()`](https://optimal2050.github.io/nestedscales/r/reference/scale_label.md)
  looks names up, returning the code where there is no label.
  `join_scale(labels = )` attaches them as `"<name>.label"`. Subsets
  keep the labels of the members that remain, and
  [`write_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
  /
  [`read_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
  carry the table.
- The data link (experimental).
  [`bind_scale()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md)
  records on a table’s code columns which scale and frame they are on;
  [`scale_link()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md)
  reports it and
  [`unbind_scale()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md)
  removes it. A bound column is a character vector of class
  `scale_member`
  ([`as_scale_member()`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_member.md),
  [`is_scale_member()`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_member.md))
  that keeps the link through subsetting, joins and row binding.
  [`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md),
  [`recast()`](https://optimal2050.github.io/nestedscales/r/reference/recast.md),
  [`recast_to_leaves()`](https://optimal2050.github.io/nestedscales/r/reference/recast_to_leaves.md),
  [`recast_from_leaves()`](https://optimal2050.github.io/nestedscales/r/reference/recast_to_leaves.md)
  and
  [`join_scale()`](https://optimal2050.github.io/nestedscales/r/reference/join_scale.md)
  take the source frame from the link, stop when the data is bound to
  another scale, and bind their result; unbound data is handled as
  before.
  [`write_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale_dataset.md)
  records the link in the store. The link is lost when a bound column is
  converted to a factor or a plain character vector, and may change or
  be removed.
- [`scale_id()`](https://optimal2050.github.io/nestedscales/r/reference/scale_id.md)
  gives the identity of a scale: its name and a hash of its structure. A
  link compares the hash alone, so objects with the same structure under
  different names are interchangeable.
- [`scale_tree()`](https://optimal2050.github.io/nestedscales/r/reference/scale_tree.md)
  lists the parts of a scale or a product as a tree and marks each one
  `fixed` (it enters the identity), `derived` or `mutable`, naming the
  function that changes it. [`str()`](https://rdrr.io/r/utils/str.html)
  prints the same tree.
  [`scale_payload_parts()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_parts.md)
  is the hook a subclass uses to describe the parts it adds.
- The classes `NestedScale` and `ScaleProduct` are exported, so printing
  one shows its properties and
  [`?NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  documents them.

### Compatibility with ‘S7’ 1.0

- The class of an object is read through
  [`S7::S7_class()`](https://rconsortium.github.io/S7/reference/S7_class.html).
  ‘S7’ 1.0 keeps it under another attribute, which stopped the label
  functions and the update of objects saved by earlier versions. ‘S7’
  0.2 is still supported.
- A test no longer depends on the wording of an ‘S7’ error message,
  which changed in ‘S7’ 1.0.

## nestedscales 0.2.0

CRAN release: 2026-11-03

### Breaking changes

- `from` and `to` are now `source` and `target` everywhere: the frame
  arguments of
  [`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md),
  [`recast_crosswalk()`](https://optimal2050.github.io/nestedscales/r/reference/recast_crosswalk.md),
  `recast_to_atoms()`, `recast_from_atoms()`,
  [`reconcile_scale()`](https://optimal2050.github.io/nestedscales/r/reference/reconcile_scale.md),
  [`recast_product()`](https://optimal2050.github.io/nestedscales/r/reference/recast_product.md)
  and the navigation functions, the scale arguments and label columns of
  [`scale_map()`](https://optimal2050.github.io/nestedscales/r/reference/scale_map.md),
  [`scale_map_between()`](https://optimal2050.github.io/nestedscales/r/reference/scale_map_between.md)
  and their registry, and the columns of `scale_atom_pairs()`.
  [`recast()`](https://optimal2050.github.io/nestedscales/r/reference/recast.md)
  takes the scale as `scale` and the source frame as `source`. The
  crosswalk columns `n_from` and `w_from` are unchanged. No deprecation
  aliases.
- [`clear_scale_rules()`](https://optimal2050.github.io/nestedscales/r/reference/clear_scale_rules.md),
  [`clear_scale_maps()`](https://optimal2050.github.io/nestedscales/r/reference/clear_scale_maps.md)
  and
  [`clear_scale_distances()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_distance.md)
  take `name` (and `scope` where it applies);
  [`clear_scale_maps()`](https://optimal2050.github.io/nestedscales/r/reference/clear_scale_maps.md)
  can now remove named keys.
- The backend helpers `.ms_*` are now the `backend_*` functions:
  [`backend_of()`](https://optimal2050.github.io/nestedscales/r/reference/backend.md)
  (errors on an unsupported input),
  [`backend_is_lazy()`](https://optimal2050.github.io/nestedscales/r/reference/backend.md),
  [`backend_schema()`](https://optimal2050.github.io/nestedscales/r/reference/backend.md),
  [`backend_lazy()`](https://optimal2050.github.io/nestedscales/r/reference/backend.md),
  [`backend_pull()`](https://optimal2050.github.io/nestedscales/r/reference/backend.md),
  [`backend_restore()`](https://optimal2050.github.io/nestedscales/r/reference/backend.md)
  and
  [`backend_bind_rows()`](https://optimal2050.github.io/nestedscales/r/reference/backend.md),
  plus the new `backend_scan()` and `backend_distinct()`. They are
  documented together under
  [`?backend`](https://optimal2050.github.io/nestedscales/r/reference/backend.md).

### New features

- Member attributes and aliases. A scale carries two optional long
  tables keyed by `(frame, unit)`: `attributes` (a value with its
  `kind`, bounds, `unit_of_measure`, `source` and `note`) and `aliases`
  (alternative labels).
  [`scale_from_leaftable()`](https://optimal2050.github.io/nestedscales/r/reference/scale_from_leaftable.md)
  takes them as `attributes=` and `aliases=`;
  [`attach_attributes_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_attributes_scale.md)
  and
  [`attach_aliases_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_aliases_scale.md)
  append rows and never overwrite;
  [`scale_attributes()`](https://optimal2050.github.io/nestedscales/r/reference/scale_attributes.md)
  reads them, resolved along the hierarchy when a frame is given;
  [`scale_aliases()`](https://optimal2050.github.io/nestedscales/r/reference/scale_aliases.md)
  and
  [`scale_match()`](https://optimal2050.github.io/nestedscales/r/reference/scale_match.md)
  resolve labels exactly and report ambiguity.
  [`convert_scale()`](https://optimal2050.github.io/nestedscales/r/reference/convert_scale.md)
  converts value columns row by row with a resolved attribute: a
  `property` is invertible, a `factor` is one-way
  (`SCALE_ATTRIBUTE_KINDS`). Both tables survive
  [`filter_scale()`](https://optimal2050.github.io/nestedscales/r/reference/filter_scale.md),
  `[`,
  [`prune_scale()`](https://optimal2050.github.io/nestedscales/r/reference/prune_scale.md)
  and clustering, which now keep a subclass as well;
  [`scale_payload_collapse()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_collapse.md)
  is the hook a subclass with a positional payload overrides for
  [`prune_scale()`](https://optimal2050.github.io/nestedscales/r/reference/prune_scale.md).
  Objects saved by 0.1.x load unchanged.
- Definition files.
  [`write_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
  and
  [`read_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
  exchange a scale as a language-neutral definition: a JSON header with
  the tables inline, or a `<name>.scale/` bundle with Arrow IPC or CSV
  tables; YAML is accepted as input and as an output option.
  [`scale_write_payload()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_io.md),
  [`scale_read_payload()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_io.md)
  and
  [`register_scale_class()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_io.md)
  let a dimension package store and restore its subclass.
- Catalogue.
  [`register_scale_dir()`](https://optimal2050.github.io/nestedscales/r/reference/scale_catalog.md),
  [`list_scale_dirs()`](https://optimal2050.github.io/nestedscales/r/reference/scale_catalog.md),
  [`clear_scale_dirs()`](https://optimal2050.github.io/nestedscales/r/reference/scale_catalog.md)
  and
  [`scale_catalog()`](https://optimal2050.github.io/nestedscales/r/reference/scale_catalog.md)
  list the definitions shipped by installed packages; `read_scale(id)`
  takes a catalogue id.
- [`write_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale_dataset.md)
  writes `_scales/manifest.json`; a legacy `manifest.yaml` is still
  read. jsonlite is a new import.

### Documentation

- New vignettes:
  [`vignette("anatomy")`](https://optimal2050.github.io/nestedscales/r/articles/anatomy.md)
  (the object, its tables and what the validator guarantees) and
  [`vignette("attributes")`](https://optimal2050.github.io/nestedscales/r/articles/attributes.md)
  (attributes, aliases and conversion). The article *Fuels, regions and
  months* on the package site joins a fuel scale, a `GeoScale` and a
  `Calendar` on one table.

## nestedscales 0.1.1

- [`write_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale_dataset.md)
  now falls back to uncompressed Arrow IPC files, with a warning, when
  the requested compression codec is unavailable in the installed Arrow
  build.

## nestedscales 0.1.0

- First release. nestedscales is the dimension-agnostic core under
  [timescales](https://github.com/optimal2050/timescales) and
  [geoscales](https://github.com/optimal2050/geoscales): their
  `Calendar` and `Geoscale` classes are subclasses of its `NestedScale`,
  so every verb below works on calendars and region hierarchies as well
  as on any other dimension.

### Scales

- A `NestedScale` is a flat table of atoms plus the ordered frames that
  group them. Build one with
  [`scale_from_leaftable()`](https://optimal2050.github.io/nestedscales/r/reference/scale_from_leaftable.md);
  read it with
  [`scale_frames()`](https://optimal2050.github.io/nestedscales/r/reference/scale_frames.md),
  `scale_units()`, `scale_key()`,
  [`scale_leaftable()`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaftable.md),
  [`scale_weights()`](https://optimal2050.github.io/nestedscales/r/reference/scale_weights.md),
  [`scale_rank()`](https://optimal2050.github.io/nestedscales/r/reference/scale_rank.md)
  and `scale_atom_level()`.
- Frames may cross-cut, and memberships may be partial (`NA`). The atoms
  may be the codes of the finest frame or, as for a calendar,
  combinations of frames held in the key column.
- [`scale_family()`](https://optimal2050.github.io/nestedscales/r/reference/scale_family.md),
  [`scale_ancestry()`](https://optimal2050.github.io/nestedscales/r/reference/scale_ancestry.md),
  [`scale_nests()`](https://optimal2050.github.io/nestedscales/r/reference/scale_nests.md),
  [`scale_children()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md),
  [`scale_parents()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md),
  [`scale_descendants()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md)
  and
  [`scale_ancestors()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md)
  navigate the hierarchy;
  [`scale_share()`](https://optimal2050.github.io/nestedscales/r/reference/scale_share.md)
  and
  [`scale_coverage()`](https://optimal2050.github.io/nestedscales/r/reference/scale_coverage.md)
  report weights.
- Frames need not nest.
  [`scale_nests()`](https://optimal2050.github.io/nestedscales/r/reference/scale_nests.md),
  [`scale_crosses()`](https://optimal2050.github.io/nestedscales/r/reference/scale_crosses.md)
  and
  [`scale_is_uniform()`](https://optimal2050.github.io/nestedscales/r/reference/scale_is_uniform.md)
  report the structure a pair of frames (or one frame) actually has,
  computed from the atoms; the order of `frames` is the convention the
  direction-dependent rules (`share`, residuals, reconciliation) follow.
- [`filter_scale()`](https://optimal2050.github.io/nestedscales/r/reference/filter_scale.md)
  (or `x[frame, unit]`) and
  [`prune_scale()`](https://optimal2050.github.io/nestedscales/r/reference/prune_scale.md)
  subset and collapse a scale, recording the result’s coverage of the
  original.
- [`scale_class()`](https://optimal2050.github.io/nestedscales/r/reference/scale_class.md),
  [`scale_is()`](https://optimal2050.github.io/nestedscales/r/reference/scale_is.md)
  and their product counterparts stand in for the classes, which are not
  exported; the package’s surface is its functions.

### Conversion

- [`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md)
  converts data between resolutions in either direction with the rules
  `sum`, `weighted_mean`, `mean`, `copy`, `sd`, `share` and `logshare`
  (`SCALE_RULES`), one per value column if needed. Other columns are
  kept as identifiers.
- `recast_to_atoms()` and `recast_from_atoms()` are the two halves of
  the route, and recast between two scales that share atom keys.
- [`recast_crosswalk()`](https://optimal2050.github.io/nestedscales/r/reference/recast_crosswalk.md)
  runs the same engine over a crosswalk built elsewhere, such as
  timescales’ mapping of one calendar onto another.
- [`recast()`](https://optimal2050.github.io/nestedscales/r/reference/recast.md)
  is the S7 generic that timescales and geoscales extend, so one
  pipeline can recast time and space in turn.
- `scale_map(x, from, to)` returns the crosswalk between two frames of a
  scale and `scale_map_between(from, to)` the one between two scales;
  [`register_scale_map()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_map.md)
  /
  [`register_scale_map_between()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_map.md)
  and
  [`register_scale_rule()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_rule.md)
  record exact crosswalks and per-column rules. A value column without a
  rule is an error, never a guess.
- [`join_scale()`](https://optimal2050.github.io/nestedscales/r/reference/join_scale.md)
  attaches a scale’s labels, coarser frames (`attach =`), shares and
  weights to a dataset.
- Declared residuals (`scale_from_leaftable(residuals = )`,
  [`scale_residuals()`](https://optimal2050.github.io/nestedscales/r/reference/scale_residuals.md))
  aggregate upward but never receive a share when a coarse value is
  split.
  [`reconcile_scale()`](https://optimal2050.github.io/nestedscales/r/reference/reconcile_scale.md)
  compares aggregated data with an independent total and can balance the
  gap.

### Data backends and large data

- Every verb accepts a `data.frame`, tibble, `data.table`, dtplyr table
  or arrow table/dataset, and returns the same class. Lazy inputs return
  a query unless `collect = TRUE`.
- A target whose sources are only partly present comes back `NA`;
  `missing_sources = "ignore"` aggregates whatever is there instead.
- `diagnostics =` controls the checks that scan the data (off by default
  for lazy inputs); `batch =` and `batch_by =` process a job in chunks
  of identifier values.

### Products of scales

- [`scale_product()`](https://optimal2050.github.io/nestedscales/r/reference/scale_product.md)
  combines several scales (time x space, …) into one multi-index without
  building its atoms.
  [`product_size()`](https://optimal2050.github.io/nestedscales/r/reference/product_size.md),
  [`product_keys()`](https://optimal2050.github.io/nestedscales/r/reference/product_keys.md),
  [`product_frames()`](https://optimal2050.github.io/nestedscales/r/reference/product_frames.md),
  [`product_weights()`](https://optimal2050.github.io/nestedscales/r/reference/product_weights.md),
  [`product_coverage()`](https://optimal2050.github.io/nestedscales/r/reference/product_coverage.md)
  and
  [`scale_axes()`](https://optimal2050.github.io/nestedscales/r/reference/scale_axes.md)
  describe it; `product_atoms()` realises the grid on request.
- [`recast_product()`](https://optimal2050.github.io/nestedscales/r/reference/recast_product.md)
  converts any subset of the axes in one call, with rules per value
  column and axis.
  [`join_product()`](https://optimal2050.github.io/nestedscales/r/reference/join_product.md)
  and
  [`filter_product()`](https://optimal2050.github.io/nestedscales/r/reference/filter_product.md)
  work axis by axis.

### Clustering

- [`cluster_scale()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_scale.md)
  groups units by their data (k-medoids, hierarchical or k-means) and
  returns the scale with the clusters as a new frame, so the rest of the
  package applies to them directly.
- [`cluster_contiguous()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_contiguous.md)
  keeps clusters contiguous in order or in an adjacency graph;
  [`cluster_medoids()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_medoids.md)
  returns representative units;
  [`cluster_sweep()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_sweep.md)
  reports cluster quality across a range of `k`.
- [`scale_distance()`](https://optimal2050.github.io/nestedscales/r/reference/scale_distance.md)
  and its registry (`SCALE_DISTANCES`,
  [`register_scale_distance()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_distance.md))
  supply level and shape distances.

### Arrays and storage

- [`as_scale_array()`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_array.md)
  and
  [`as_scale_table()`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_array.md)
  convert between long data and a dense array over a scale or product.
- [`write_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale_dataset.md),
  [`open_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/open_scale_dataset.md)
  and
  [`scale_dataset_info()`](https://optimal2050.github.io/nestedscales/r/reference/scale_dataset_info.md)
  store data as a partitioned Arrow dataset together with its scales, so
  it reopens ready to recast.

### Building a dimension package

- [`vignette("nestedscales")`](https://optimal2050.github.io/nestedscales/r/articles/nestedscales.md)
  introduces the representation and the main functions; the [package
  website](https://optimal2050.github.io/nestedscales/) includes a
  roadmap of what the package offers and what is planned.
- A dimension package defines a `NestedScale` subclass, as timescales
  and geoscales do.
  [`scale_alias_property()`](https://optimal2050.github.io/nestedscales/r/reference/scale_alias_property.md)
  gives an inherited property the dimension’s own name;
  [`scale_vocab()`](https://optimal2050.github.io/nestedscales/r/reference/scale_vocab.md)
  puts the dimension’s words in error messages;
  [`scale_payload_slice()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_slice.md)
  keeps per-atom data (such as geometry) in step when rows are subset;
  `scale_atom_pairs()` lets a dimension generate its atom layer.
- `.ms_backend()` and the other `.ms_*` helpers provide the backend
  handling to packages built on nestedscales.
