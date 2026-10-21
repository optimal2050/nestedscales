# nestedscales API

The language-neutral contract every binding implements. Each function has the
**same name and argument order** in every language, and is called as a free
function: `scale_frames(s)` in R and Julia, `ns.scale_frames(s)` in Python,
`nestedscales::scale_frames(s)` in C++.

Correctness is checked against the R package: `specs/goldens/generate.R`
writes the cases, and every binding replays them.

## Type mapping

| Concept | R | Python |
|---|---|---|
| scale | S7 `NestedScale` | frozen dataclass `NestedScale` |
| table | `data.frame` / lazy arrow | `pyarrow.Table` (accepts polars, pandas) |
| character vector | `character` | `list[str]` (a bare `str` is one element) |
| missing | `NULL` / `NA` | `None` |
| verdict with evidence | logical + attribute `offenders` / `sizes` | `Verdict(ok, offenders, sizes)`; truthy, `== bool` |
| error | `stop()` | `NestedScalesError` (a `ValueError`) |
| warning | `warning()` | `NestedScalesWarning` |
| summary | `summary(x)` | `scale_summary(x)` |
| print | `print(x)` | `str(x)`; `repr(x)` is the one-line `format()` |
| subclass hook | S7 generic | `functools.singledispatch` |
| source / target argument | `source` / `target` | `source` / `target` |
| named vector argument (`rule = c(a = "sum")`) | named vector or list | `dict` |
| lazy input | arrow Dataset / dtplyr | `pyarrow.dataset.Dataset`, polars `LazyFrame` |
| `x[frame, unit]` | `[.NestedScale` | `x[frame, unit]` (`__getitem__`) |
| dense array | `array` with dimnames | `numpy.ndarray`; labels are `scale_units()` |

Rows of returned tables are sorted by code point in Python and by the session
locale in R, so row order is not part of the contract. Code vocabularies
(`scale_units`, children, parents) are in canonical member order everywhere.

Error and warning messages are kept verbatim across bindings.

Missing values follow R: an aggregate over a group containing a missing value
is missing, and a target whose sources are only partly present in the data is
missing (the partial-source law). A lazy input returns the observed target
units only unless `collect = TRUE`; a materialised result is completed to the
full target vocabulary, identifier groups in first-appearance order and target
codes in member order, a missing-target row last.

Known differences:

* a filtered scale whose codes are too long to list is named with a hash of
  them; R uses `rlang::hash()`, which cannot be reproduced outside R, so such
  names differ between bindings;
* R's YAML writer stores named numbers (`coverage`, `parent_totals`, a
  Calendar's `tokens`) as bare sequences rounded to 7 digits; the Python
  reader maps them back onto the declared weights and recomputes coverage
  from the parent totals, and the Python writer stores named mappings at full
  precision.

## Functions

Status: **R** = in the R package; **Py** = in the Python binding.

Signatures are the agreed ones. Three renames landed in R 0.2.0 with no
deprecation aliases (the R package is pre-1.0), matching Python:

* `from` / `to` became `source` / `target` everywhere: frames, scales,
  crosswalk columns, navigation, and the atom-pair columns. In `recast()`,
  the scale argument is `scale` and the source frame `source`;
* the `clear_*` functions take `name` (registry names or keys) and `scope`;
* the backend helpers `.ms_*` became the `backend_*` functions below.

### Construct and inspect

| Function | Arguments | Returns | R | Py |
|---|---|---|---|---|
| `scale_from_leaftable` | `leaftable, frames, key=NULL, weights=NULL, default_weight=NULL, members=NULL, name="", desc="", attributes=NULL, aliases=NULL, ...` | scale | ✓ | ✓ |
| `scale_example` | | scale (7 atoms) | ✓ | ✓ |
| `scale_example2` | | scale (4 atoms) | ✓ | ✓ |
| `is_valid_frame` | `x` | logical per name | ✓ | ✓ |
| `scale_frames` | `x, finest=FALSE` | names, coarsest first | ✓ | ✓ |
| `scale_units` | `x, frame=NULL` | codes at a frame (default: atoms) | ✓ | ✓ |
| `scale_rank` | `x, frame` | 1 = coarsest; key = n+1; else missing | ✓ | ✓ |
| `scale_atom_level` | `x` | finest frame, or the key | ✓ | ✓ |
| `scale_key` | `x` | key column name | ✓ | ✓ |
| `scale_leaftable` | `x` | table | ✓ | ✓ |
| `scale_weights` | `x` | weight column names | ✓ | ✓ |
| `scale_residuals` | `x, frame=NULL` | frame → codes, or codes | ✓ | ✓ |
| `scale_coverage` | `x, weight=NULL` | weight → fraction, or one fraction | ✓ | ✓ |
| `scale_vocab` | `x` | dimension words for messages | ✓ | ✓ |
| `scale_payload_slice` | `x, i` | `x` with payload subset | ✓ | ✓ |
| `scale_payload_collapse` | `x, map` | `x` with payload collapsed by `map` (old row → new row, missing = dropped); default identity | ✓ | ✓ |
| `scale_alias_property` | `name` | alias property for subclasses | ✓ | ✓ |
| `scale_is` | `x` | logical | ✓ | ✓ |
| `scale_class` | | the class | ✓ | ✓ |
| `summary` / `scale_summary` | `x` | summary object | ✓ | ✓ |

### Navigate

| Function | Arguments | Returns | R | Py |
|---|---|---|---|---|
| `scale_family` | `x, parent=NULL, child=NULL` | table `parent_frame, parent, child_frame, child` | ✓ | ✓ |
| `scale_ancestry` | `x` | same table, all frame pairs | ✓ | ✓ |
| `scale_nests` | `x, parent, child` | verdict, `offenders` | ✓ | ✓ |
| `scale_crosses` | `x, a, b` | verdict, `offenders` | ✓ | ✓ |
| `scale_is_uniform` | `x, frame, weight=NULL, tolerance=1e-9` | verdict, `sizes` | ✓ | ✓ |
| `scale_children` | `x, frame, unit, target=NULL` | codes | ✓ | ✓ |
| `scale_parents` | `x, frame, unit, target=NULL` | codes | ✓ | ✓ |
| `scale_descendants` | `x, frame, unit, target=NULL` | table `frame, unit` | ✓ | ✓ |
| `scale_ancestors` | `x, frame, unit, target=NULL` | table `frame, unit` | ✓ | ✓ |

### Rules

| Function | Arguments | Returns | R | Py |
|---|---|---|---|---|
| `SCALE_RULES` | | `sum, weighted_mean, mean, copy, sd, share, logshare` | ✓ | ✓ |
| `register_scale_rule` | `param, rule, weight=NULL, scope=NULL` | the entry | ✓ | ✓ |
| `get_scale_rule` | `param, scope=NULL` | entry `rule, weight, scope`, or missing | ✓ | ✓ |
| `list_scale_rules` | `scope=NULL` | table `param, rule, weight, scope` | ✓ | ✓ |
| `clear_scale_rules` | `name=NULL, scope=NULL` | nothing | ✓ | ✓ |

A rule name may be a unique prefix (`"weighted"`), as with R's `match.arg()`.
A scoped lookup falls back to the unscoped entry. A value column with no rule
(explicit or registered) is an error.

### Maps

| Function | Arguments | Returns | R | Py |
|---|---|---|---|---|
| `scale_atom_pairs` | `x, source, target, weight=NULL, ...` | table `source, target, w` (subclass hook) | ✓ | ✓ |
| `scale_map` | `x, source, target, weight=NULL, by=character(), ...` | crosswalk | ✓ | ✓ |
| `scale_map_between` | `source, target, weight=NULL` | crosswalk | ✓ | ✓ |
| `register_scale_map` | `x, source, target, map` | registry key | ✓ | ✓ |
| `register_scale_map_between` | `source, target, map` | registry key | ✓ | ✓ |
| `get_scale_map` | `x, source, target` | map, or missing | ✓ | ✓ |
| `get_scale_map_between` | `source, target` | map, or missing | ✓ | ✓ |
| `list_scale_maps` | | table `key` | ✓ | ✓ |
| `clear_scale_maps` | `name=NULL` | nothing | ✓ | ✓ |

A crosswalk has columns `<source label>, <target label>, n_from, n_overlap, w,
w_from` (plus any `by` columns first). `n_from` and `n_overlap` are 32-bit
integers, `w` and `w_from` doubles. A missing target label marks atoms the
target does not cover. The split share of `sum` disaggregation is
`w / w_from`; with no weight column every atom weighs 1, so it equals
`n_overlap / n_from`.

### Recast

| Function | Arguments | Returns | R | Py |
|---|---|---|---|---|
| `recast_scale` | `data, x, source=NULL, target, key=NULL, values=NULL, rule=NULL, weight=NULL, na_action="drop", parent=NULL, collect=NULL, diagnostics="auto", missing_sources="na", batch=NULL, batch_by=NULL, ...` | table keyed at `target` (`source` for the share rules) | ✓ | ✓ |
| `recast_crosswalk` | `data, map, source, target, key=source, values=NULL, rule=NULL, ids=NULL, by=character(), targets=NULL, missing_sources="na", unit="unit", collect=NULL` | table keyed at `target` | ✓ | ✓ |
| `recast_to_atoms` | `data, x, source=NULL, key=NULL, values=NULL, rule=NULL, weight=NULL, attach_weight=TRUE, collect=NULL` | table keyed at the atoms | ✓ | ✓ |
| `recast_from_atoms` | `data, x, target, key=NULL, values=NULL, rule=NULL, weight=NULL, na_rm=FALSE, na_action="drop", collect=NULL` | table keyed at `target` | ✓ | ✓ |
| `recast` | `x, scale, ...` | dispatches on the scale | ✓ | ✓ |

### Subset, collapse, attach

| Function | Arguments | Returns | R | Py |
|---|---|---|---|---|
| `filter_scale` | `x, frame, unit, drop_empty_frames=FALSE` | scale (a sample) | ✓ | ✓ |
| `prune_scale` | `x, frame` | scale | ✓ | ✓ |
| `scale_share` | `x, frame, weight=NULL, within=NULL` | table | ✓ | ✓ |
| `join_scale` | `data, x, key=NULL, frame=NULL, attach=NULL, meta=FALSE, weight=NULL, as_factor=TRUE, collect=NULL, diagnostics="auto"` | `data` plus attached columns | ✓ | ✓ |
| `as_scale_array` | `data, x, value=NULL, frames=NULL, fill=NA, limit=1e7` | dense array | ✓ | one scale |
| `as_scale_table` | `a, x, value="value", frames=NULL, drop_na=TRUE` | table | ✓ | one scale |

`as_factor = TRUE` gives an R factor, and a dictionary column in Python.

### Attributes and aliases

Member attributes (a calorific value, an emission factor) and aliases
(alternative labels) are long tables on the scale keyed by `(frame, unit)`.
Attributes are never weights and are never recast; `convert_scale()` applies
them row by row. A `kind` travels with every attribute row: `property` is an
invertible ratio, `factor` is one-way.

| Function | Arguments | Returns | R | Py |
|---|---|---|---|---|
| `SCALE_ATTRIBUTE_KINDS` | | `property, factor` | ✓ | ✓ |
| `attach_attributes_scale` | `x, attributes, source=NULL, kind=NULL` | `x` with rows appended; an existing `(frame, unit, attribute, source)` row is an error | ✓ | ✓ |
| `scale_attributes` | `x, attribute=NULL, frame=NULL, source=NULL, inherit=TRUE` | stored rows; with `frame=` one row per member and attribute, resolved along the hierarchy (`origin_frame`, `origin_unit`) | ✓ | ✓ |
| `attach_aliases_scale` | `x, aliases, source=NULL` | `x` with rows appended | ✓ | ✓ |
| `scale_aliases` | `x, frame=NULL, source=NULL` | alias rows | ✓ | ✓ |
| `scale_match` | `x, labels, frame=NULL, source=NULL` | table `label, frame, unit, method, candidates`; `method` = `exact`, `alias`, `ambiguous`, `none` | ✓ | ✓ |
| `convert_scale` | `data, x, attribute, from_unit, to_unit, key=NULL, frame=NULL, values=NULL, source=NULL, na_action="error", collect=NULL` | `data` with value columns converted plus `<attribute>` and `<attribute>.origin_frame` | ✓ | ✓ |

### Backends

For dimension packages: accept the same inputs as the core verbs and return
results in the caller's type.

| Function | Arguments | Returns | R | Py |
|---|---|---|---|---|
| `backend_of` | `data, arg="data"` | the backend (errors on an unsupported input) | ✓ | ✓ |
| `backend_is_lazy` | `backend` | logical | ✓ | ✓ |
| `backend_schema` | `data, backend=NULL` | column names and types, no scan | ✓ | ✓ |
| `backend_scan` | `data, backend=NULL, columns=NULL, filter=NULL` | the needed columns and rows | ✓ | ✓ |
| `backend_pull` | `table` | an in-memory table | ✓ | ✓ |
| `backend_restore` | `table, backend, collect=NULL` | the caller's type | ✓ | ✓ |
| `backend_bind_rows` | `parts` | one table | ✓ | ✓ |
| `backend_distinct` | `data, columns, backend=NULL` | distinct rows, first-appearance order | ✓ | ✓ |
| `backend_lazy` | `data, backend=NULL` | a dplyr carrier for a pipeline (R's lazy lift; Python has no need for it) | ✓ | — |

### Store

| Function | Arguments | Returns | R | Py |
|---|---|---|---|---|
| `write_scale_dataset` | `data, x, path, partitioning=NULL, compression="zstd", overwrite=FALSE` | `path` | ✓ | ✓ |
| `open_scale_dataset` | `path` | `data` (lazy) + `scale` | ✓ | ✓ |
| `scale_dataset_info` | `path` | kind, axes, keys, files, bytes | ✓ | ✓ |

The store's manifest is `_scales/manifest.json` (one definition header per
axis); a legacy `manifest.yaml` is still read.

### Definitions and catalogue

A definition is a language-neutral file: a JSON header (`schema_version`,
`class`, `name`, `key`, `frames`, `members`, `meta`, `tables`, `payload`) with
the leaftable, attribute and alias tables inline (column-wise, typed) or, in a
`<name>.scale/` bundle directory, as Arrow IPC or CSV files. YAML is accepted
as input and optional output. The core ships `carriers` (fuels and energy
carriers with IPCC 2006 defaults) and reads definitions from every registered
directory.

| Function | Arguments | Returns | R | Py |
|---|---|---|---|---|
| `write_scale` | `x, path, format="json", tables="auto", overwrite=FALSE` | `path`; `.json`/`.yaml` = one file, otherwise a bundle directory | ✓ | ✓ |
| `read_scale` | `path, package=NULL, class="stored"` | the scale (a registered subclass, or the core with `class="core"`); `path` may be a catalogue id | ✓ | ✓ |
| `scale_catalog` | | table `id, name, kind, key, frames, n_atoms, package, path` | ✓ | ✓ |
| `register_scale_dir` | `path, package=NULL` | registry key | ✓ | ✓ |
| `list_scale_dirs` | | registered directories | ✓ | ✓ |
| `clear_scale_dirs` | | nothing | ✓ | ✓ |
| `register_scale_class` | `class` | registry key (qualified class name) | ✓ | ✓ |
| `list_scale_classes` | | registered class names | ✓ | ✓ |
| `scale_write_payload` | `x, dir, header` | the header with payload entries (subclass hook; default identity) | ✓ | ✓ |
| `scale_read_payload` | `x, dir, header` | the subclass object (subclass hook; default identity) | ✓ | ✓ |

### Products

| Function | Arguments | Returns | R | Py |
|---|---|---|---|---|
| `scale_product` | `..., name="", desc="", keys=NULL, joint_weights=NULL` | product | ✓ | ✓ |
| `scale_axes`, `product_keys`, `product_frames`, `product_size`, `product_weights`, `product_coverage` | `x, ...` | accessors | ✓ | ✓ |
| `scale_is_product`, `scale_product_class` | | | ✓ | ✓ |
| `recast_product`, `join_product`, `filter_product`, `product_atoms` | | | ✓ | — |

### R only for now

`reconcile_scale`, `cluster_scale`, `cluster_medoids`, `cluster_contiguous`,
`cluster_sweep`, `scale_distance` and its registry.
