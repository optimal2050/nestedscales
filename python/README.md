# nestedscales (Python)

Python binding of the R package
[nestedscales](https://github.com/optimal2050/nestedscales): multi-level
discrete scales for modelling. A scale records its finest units (atoms) and
their membership in coarser levels (frames) -- nested, cross-cutting or
partially covered -- and data is recast between levels through the atoms,
with an explicit, direction-aware rule per value column.

```python
import pyarrow as pa
import nestedscales as ns

s = ns.scale_example()
print(s)

d = pa.table({"unit": ["U1", "U2", "U3", "U4", "U5", "U6"],
              "capacity": [1.0, 2, 3, 4, 5, 6]})
ns.recast_scale(d, s, source="unit", target="sector", rule="sum")  # aggregate
y = pa.table({"sector": ["P", "S"], "capacity": [10.0, 20]})
ns.recast_scale(y, s, source="sector", target="class", rule="sum",
                weight="size")                                     # split by weight
ns.join_scale(d, s, attach=True)                                  # attach labels
```

## One API, several languages

Every function has the **same name and argument order** as in R, and is a
free function (`ns.scale_frames(s)`, not `s.frames()`). `API.md` at the
repository root is the shared specification. Python-specific spellings:

* the source/target arguments are `source` and `target`, the agreed names
  for every binding; R still spells them `from`/`to` until 0.2.0;
* R's `summary(x)` is `scale_summary(x)`;
* a logical with an `offenders`/`sizes` attribute is a `Verdict`, which is
  truthy and compares equal to a bool.

Error and warning messages are the R package's, verbatim apart from the
argument names. Correctness is
checked against R: `specs/goldens/generate.R` writes several hundred cases
from the R source, and the test suite replays every one.

## Data backends

The engine computes on `pyarrow`. Inputs may be a `pyarrow.Table`, pandas,
polars or a dict of columns, and results come back in the caller's type. A
`pyarrow.dataset.Dataset` or polars `LazyFrame` is lazy: only the needed
columns are scanned, `batch=`/`batch_by=` push a filter into the scan, and
without `collect=True` the result holds the observed target units only, as in
R.

Dimension packages build on the public `backend_*` functions
(`backend_of`, `backend_scan`, `backend_restore`, ...) to accept the same
inputs and return the caller's type.

## Stores shared with R

`write_scale_dataset()` / `open_scale_dataset()` read and write the R
package's store -- hive-partitioned Arrow IPC data plus a JSON manifest and
Arrow leaftables (a legacy YAML manifest is still read) -- so data and its
scales move between R and Python unchanged. `write_scale()` / `read_scale()`
exchange single definition files and bundles (JSON header; inline, Arrow or
CSV tables), and `read_scale("carriers")` opens the fuel taxonomy vendored
with the binding (`scale_catalog()` lists every registered definition). Scales written by R's timescales and geoscales are restored as
Calendars and GeoScales by the Python timescales and geoscales packages
(`as_calendar()`, `as_geoscale()`).

## Scope

Ported: the scale class, construction, navigation, rules, maps, the whole
recast engine (`recast_scale`, `recast_crosswalk`, `recast_to_atoms`,
`recast_from_atoms`), filter/prune/share/join, 1-D arrays, the dataset store,
and the `ScaleProduct` container. R only for now: `recast_product()` and the
other product verbs, `reconcile_scale()`, and clustering.

## Development

```sh
python -m venv .venv && .venv/Scripts/python -m pip install -e ".[test,polars,pandas]"
.venv/Scripts/python -m pytest -q
Rscript specs/goldens/generate.R      # from the repository root, to refresh goldens
```
