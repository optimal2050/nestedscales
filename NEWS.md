# nestedscales 0.2.0

## Breaking changes

* `from` and `to` are now `source` and `target` everywhere: the frame
  arguments of `recast_scale()`, `recast_crosswalk()`, `recast_to_atoms()`,
  `recast_from_atoms()`, `reconcile_scale()`, `recast_product()` and the
  navigation functions, the scale arguments and label columns of
  `scale_map()`, `scale_map_between()` and their registry, and the columns of
  `scale_atom_pairs()`. `recast()` takes the scale as `scale` and the source
  frame as `source`. The crosswalk columns `n_from` and `w_from` are
  unchanged. No deprecation aliases.
* `clear_scale_rules()`, `clear_scale_maps()` and `clear_scale_distances()`
  take `name` (and `scope` where it applies); `clear_scale_maps()` can now
  remove named keys.
* The backend helpers `.ms_*` are now the `backend_*` functions: `backend_of()`
  (errors on an unsupported input), `backend_is_lazy()`, `backend_schema()`,
  `backend_lazy()`, `backend_pull()`, `backend_restore()` and
  `backend_bind_rows()`, plus the new `backend_scan()` and
  `backend_distinct()`. They are documented together under `?backend`.

## New features

* Member attributes and aliases. A scale carries two optional long tables
  keyed by `(frame, unit)`: `attributes` (a value with its `kind`, bounds,
  `unit_of_measure`, `source` and `note`) and `aliases` (alternative labels).
  `scale_from_leaftable()` takes them as `attributes=` and `aliases=`;
  `attach_attributes_scale()` and `attach_aliases_scale()` append rows and
  never overwrite; `scale_attributes()` reads them, resolved along the
  hierarchy when a frame is given; `scale_aliases()` and `scale_match()`
  resolve labels exactly and report ambiguity. `convert_scale()` converts
  value columns row by row with a resolved attribute: a `property` is
  invertible, a `factor` is one-way (`SCALE_ATTRIBUTE_KINDS`). Both tables
  survive `filter_scale()`, `[`, `prune_scale()` and clustering, which now
  keep a subclass as well; `scale_payload_collapse()` is the hook a subclass
  with a positional payload overrides for `prune_scale()`. Objects saved by
  0.1.x load unchanged.
* Definition files. `write_scale()` and `read_scale()` exchange a scale as a
  language-neutral definition: a JSON header with the tables inline, or a
  `<name>.scale/` bundle with Arrow IPC or CSV tables; YAML is accepted as
  input and as an output option. `scale_write_payload()`,
  `scale_read_payload()` and `register_scale_class()` let a dimension
  package store and restore its subclass.
* Catalogue. `register_scale_dir()`, `list_scale_dirs()`,
  `clear_scale_dirs()` and `scale_catalog()` list the definitions shipped by
  installed packages; `read_scale(id)` takes a catalogue id.
* Shipped definition `carriers`: 71 fuels in `group > carrier > fuel` from
  the energypal taxonomy, with the IPCC 2006 default net calorific values
  and CO2 emission factors as attributes and energypal's spellings and model
  commodity codes as aliases (`?shipped_scales`). The IPCC tables ship as
  `inst/extdata/ipcc2006_fuel_defaults.csv`.
* `write_scale_dataset()` writes `_scales/manifest.json`; a legacy
  `manifest.yaml` is still read. jsonlite is a new import.

## Documentation

* New vignettes: `vignette("anatomy")` (the object, its tables and what the
  validator guarantees) and `vignette("attributes")` (attributes, aliases
  and conversion on the shipped `carriers`). The article *Fuels, regions
  and months* on the package site joins a fuel scale, a `GeoScale` and a
  `Calendar` on one table.

# nestedscales 0.1.1

* `write_scale_dataset()` now falls back to uncompressed Arrow IPC files, with
  a warning, when the requested compression codec is unavailable in the
  installed Arrow build.

# nestedscales 0.1.0

* First release. nestedscales is the dimension-agnostic core under
  [timescales](https://github.com/optimal2050/timescales) and
  [geoscales](https://github.com/optimal2050/geoscales): their `Calendar` and
  `Geoscale` classes are subclasses of its `NestedScale`, so every verb below works
  on calendars and region hierarchies as well as on any other dimension.

## Scales

* A `NestedScale` is a flat table of atoms plus the ordered frames that group them.
  Build one with `scale_from_leaftable()`; read it with `scale_frames()`,
  `scale_units()`, `scale_key()`, `scale_leaftable()`, `scale_weights()`,
  `scale_rank()` and `scale_atom_level()`.
* Frames may cross-cut, and memberships may be partial (`NA`). The atoms may
  be the codes of the finest frame or, as for a calendar, combinations of
  frames held in the key column.
* `scale_family()`, `scale_ancestry()`, `scale_nests()`, `scale_children()`,
  `scale_parents()`, `scale_descendants()` and `scale_ancestors()` navigate
  the hierarchy; `scale_share()` and `scale_coverage()` report weights.
* Frames need not nest. `scale_nests()`, `scale_crosses()` and
  `scale_is_uniform()` report the structure a pair of frames (or one frame)
  actually has, computed from the atoms; the order of `frames` is the
  convention the direction-dependent rules (`share`, residuals,
  reconciliation) follow.
* `filter_scale()` (or `x[frame, unit]`) and `prune_scale()` subset and
  collapse a scale, recording the result's coverage of the original.
* `scale_class()`, `scale_is()` and their product counterparts stand in for
  the classes, which are not exported; the package's surface is its functions.

## Conversion

* `recast_scale()` converts data between resolutions in either direction with
  the rules `sum`, `weighted_mean`, `mean`, `copy`, `sd`, `share` and
  `logshare` (`SCALE_RULES`), one per value column if needed. Other columns
  are kept as identifiers.
* `recast_to_atoms()` and `recast_from_atoms()` are the two halves of the
  route, and recast between two scales that share atom keys.
* `recast_crosswalk()` runs the same engine over a crosswalk built elsewhere,
  such as timescales' mapping of one calendar onto another.
* `recast()` is the S7 generic that timescales and geoscales extend, so one
  pipeline can recast time and space in turn.
* `scale_map(x, from, to)` returns the crosswalk between two frames of a
  scale and `scale_map_between(from, to)` the one between two scales;
  `register_scale_map()` / `register_scale_map_between()` and
  `register_scale_rule()` record exact crosswalks and per-column rules.
  A value column without a rule is an error, never a guess.
* `join_scale()` attaches a scale's labels, coarser frames (`attach =`),
  shares and weights to a dataset.
* Declared residuals (`scale_from_leaftable(residuals = )`,
  `scale_residuals()`) aggregate upward but never receive a share when a
  coarse value is split. `reconcile_scale()` compares aggregated data with an
  independent total and can balance the gap.

## Data backends and large data

* Every verb accepts a `data.frame`, tibble, `data.table`, dtplyr table or
  arrow table/dataset, and returns the same class. Lazy inputs return a query
  unless `collect = TRUE`.
* A target whose sources are only partly present comes back `NA`;
  `missing_sources = "ignore"` aggregates whatever is there instead.
* `diagnostics =` controls the checks that scan the data (off by default for
  lazy inputs); `batch =` and `batch_by =` process a job in chunks of
  identifier values.

## Products of scales

* `scale_product()` combines several scales (time x space, ...) into one
  multi-index without building its atoms. `product_size()`, `product_keys()`,
  `product_frames()`, `product_weights()`, `product_coverage()` and
  `scale_axes()` describe it; `product_atoms()` realises the grid on request.
* `recast_product()` converts any subset of the axes in one call, with rules
  per value column and axis. `join_product()` and `filter_product()` work axis
  by axis.

## Clustering

* `cluster_scale()` groups units by their data (k-medoids, hierarchical or
  k-means) and returns the scale with the clusters as a new frame, so the
  rest of the package applies to them directly.
* `cluster_contiguous()` keeps clusters contiguous in order or in an adjacency
  graph; `cluster_medoids()` returns representative units; `cluster_sweep()`
  reports cluster quality across a range of `k`.
* `scale_distance()` and its registry (`SCALE_DISTANCES`,
  `register_scale_distance()`) supply level and shape distances.

## Arrays and storage

* `as_scale_array()` and `as_scale_table()` convert between long data and a
  dense array over a scale or product.
* `write_scale_dataset()`, `open_scale_dataset()` and `scale_dataset_info()`
  store data as a partitioned Arrow dataset together with its scales, so it
  reopens ready to recast.

## Building a dimension package

* `vignette("nestedscales")` introduces the representation and the main
  functions; the [package website](https://optimal2050.github.io/nestedscales/)
  includes a roadmap of what the package offers and what is planned.
* A dimension package defines a `NestedScale` subclass, as timescales and
  geoscales do. `scale_alias_property()` gives an inherited property the dimension's own
  name; `scale_vocab()` puts the dimension's words in error messages;
  `scale_payload_slice()` keeps per-atom data (such as geometry) in step when
  rows are subset; `scale_atom_pairs()` lets a dimension generate its atom
  layer.
* `.ms_backend()` and the other `.ms_*` helpers provide the backend handling
  to packages built on nestedscales.
