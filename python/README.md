# nestedscales (Python)

Python binding of the R package
[nestedscales](https://github.com/optimal2050/nestedscales): multi-level
discrete scales for modelling. A scale records its finest members (the
leaves) and their membership in coarser levels (frames) -- nested,
cross-cutting or partially covered -- and data is recast between levels
through the leaves, with an explicit, direction-aware rule per value column.
This binding follows the R package at version 0.3.0.

A *frame* is one level of a scale, a *member* one item of a frame, a *leaf* a
member of the finest layer and one row of the leaftable, and the *leaf
column* the column of the leaftable that identifies the leaves. "Unit" means
a unit of measure only.

```python
import pyarrow as pa
import nestedscales as ns

s = ns.scale_example()
print(s)

d = pa.table({"item": ["U1", "U2", "U3", "U4", "U5", "U6"],
              "capacity": [1.0, 2, 3, 4, 5, 6]})
ns.recast_scale(d, s, source="item", target="sector", rule="sum")  # aggregate
y = pa.table({"sector": ["P", "S"], "capacity": [10.0, 20]})
ns.recast_scale(y, s, source="sector", target="class", rule="sum",
                weight="size")                                     # split by weight
ns.join_scale(d, s, attach=True)                                  # attach codes

ns.scale_id(s)           # "example@c24a3e23", the same string as in R
print(ns.scale_tree(s))  # the parts of the scale: fixed, derived or mutable
```

## One API, several languages

Every function has the **same name and argument order** as in R, and is a
free function (`ns.scale_frames(s)`, not `s.frames()`). `API.md` at the
repository root is the shared specification. Python-specific spellings:

* R's `summary(x)` is `scale_summary(x)`, and `print(x)` is `str(x)`;
* R's `x@leaf` is `x.leaf`; `read_scale(class=)` is `read_scale(cls=)`;
* a subclass hook is a `functools.singledispatch` function where R has an S7
  generic;
* a logical with an `offenders`/`sizes` attribute is a `Verdict`, which is
  truthy and compares equal to a bool.

Error and warning messages are the R package's, verbatim. Correctness is
checked against R: `specs/goldens/generate.R` writes several hundred cases
from the R source, and the test suite replays every one.

## Labels, identity, tree

A scale carries three optional member tables keyed by `(frame, member)`:
attributes (`attach_attributes_scale()`, `scale_attributes()`), aliases
(`attach_aliases_scale()`, `scale_aliases()`, `scale_match()`) and labels.
Labels are display names in named variants: `attach_labels_scale()` adds
rows and sets the default variant, `scale_labels()` reads the table,
`scale_label()` looks names up and returns the code where there is no label,
and `join_scale(labels=)` attaches them as `"<name>.label"`. A label row
with a null `member` names the frame itself. Subsets keep the rows of the
members that remain.

`scale_id()` is the identity of a scale, `"<name>@<hash>"`: the hash covers
the leaf column, the frames and the leaf-to-frame memberships, and is the
same in R and Python for the same scale. `scale_tree()` lists the parts of a
scale or a product and marks each `fixed` (it enters the identity),
`derived` or `mutable`.

## Data backends

The engine computes on `pyarrow`. Inputs may be a `pyarrow.Table`, pandas,
polars or a dict of columns, and results come back in the caller's type. A
`pyarrow.dataset.Dataset` or polars `LazyFrame` is lazy: only the needed
columns are scanned, `batch=`/`batch_by=` push a filter into the scan, and
without `collect=True` the result holds the observed target members only, as in
R.

Dimension packages build on the public `backend_*` functions
(`backend_of`, `backend_pull`, `backend_restore`, ...) to accept the same
inputs and return the caller's type.

## Stores shared with R

`write_scale_dataset()` / `open_scale_dataset()` read and write the R
package's store -- hive-partitioned Arrow IPC data plus a JSON manifest and
Arrow leaftables (a legacy YAML manifest is still read) -- so data and its
scales move between R and Python unchanged. `write_scale()` / `read_scale()`
exchange single definition files and bundles (JSON header; inline, Arrow or
CSV tables); `scale_catalog()` lists every registered definition and
`read_scale()` opens one by its id. Definitions are written with schema
version 2 (the header field `leaf`, the table column `member`) and versions 1
and 2 are read. A scale held in `meta` is written as a reference, its name
and `scale_id()`, and reads back as `{"_scale": {"name": ..., "id": ...}}`.

## Subclasses

A dimension package subclasses `NestedScale` and registers methods on the
hooks, each a `functools.singledispatch` function:

| Hook | Called | Default |
|---|---|---|
| `scale_vocab(x)` | for the words of messages | the neutral vocabulary |
| `scale_payload_slice(x, i)` | after a row subset (`filter_scale()`, `x[frame, member]`); `i` = 0-based kept rows | `x` |
| `scale_payload_collapse(x, map)` | after a collapse (`prune_scale()`); `map` = new row of each former row, None = dropped | `x` |
| `scale_write_payload(x, dir, header)` | by `write_scale()`, after the core tables | `header` |
| `scale_read_payload(x, dir, header)` | by `read_scale()`, with the core scale; registered for the subclass | `x` |
| `scale_payload_parts(x)` | by `scale_tree()` | nothing |
| `scale_leaf_pairs(x, source, target, weight)` | by `scale_map()` | from the leaftable |

A slice or collapse method receives the object with its core fields already
replaced and not yet validated, changes what it must with
`scale_set_props(x, **fields)` (a copy that keeps the concrete class; any
field may be named, the leaf column included) and returns it; the engine
validates once at the end. `register_scale_class()` makes `read_scale()`
return the subclass, and `scale_alias_property()` names an inherited field
in the words of the dimension.

The leaftable may carry numeric columns that are not weights: only the
columns named in `meta["weights"]` are weights, with `meta["default_weight"]`
the one used when none is named. A weight may be zero on some leaves but not
on all of them. A subset records `meta["coverage"]` and
`meta["parent_totals"]` per weight name, and `prune_scale()` sums the weight
columns and drops the other columns.

## Scope

Ported: the scale class, construction, navigation, rules, maps, the whole
recast engine (`recast_scale`, `recast_crosswalk`, `recast_to_leaves`,
`recast_from_leaves`), filter/prune/share/join, attributes, aliases and
labels, `scale_id()` and `scale_tree()`, definition files and the catalogue,
1-D arrays, the dataset store, and the `ScaleProduct` container. R only for
now: the data link (`bind_scale()`, `scale_link()`, the `scale_member`
vector), `recast_product()` and the other product verbs, `reconcile_scale()`,
distances and clustering. The R package marks as experimental, which means
they may change or be removed: attributes with `convert_scale()`, products,
arrays and stored datasets; the same holds here.

## Provenance

The R package is the original implementation. This Python binding was
translated from it with the AI coding assistant Claude Code, function by
function, and is checked against results generated from the R sources
(`specs/goldens/`). Human review and contributions are very welcome; issues and pull
requests go to <https://github.com/optimal2050/nestedscales>.

## Development

```sh
python -m venv .venv && .venv/Scripts/python -m pip install -e ".[test,polars,pandas]"
.venv/Scripts/python -m pytest -q
Rscript specs/goldens/generate.R      # from the repository root, to refresh goldens
```
