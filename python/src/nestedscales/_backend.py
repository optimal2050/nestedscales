"""Table backends (port of R/backend.R).

The engine computes on `pyarrow.Table`. Inputs:

* eager: `pyarrow.Table`/`RecordBatch`, pandas, polars `DataFrame`, a dict of
  columns, or anything speaking the Arrow PyCapsule stream protocol;
* lazy: `pyarrow.dataset.Dataset` and polars `LazyFrame`. They are scanned
  with column projection (and, for batching, a pushed-down filter). Without
  `collect=True` a lazy input returns the observed rows only, skipping the
  vocabulary completion -- the R lazy contract.

Results come back in the caller's type (`restore`).
"""
from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np
import pyarrow as pa
import pyarrow.compute as pc

from ._utils import _stop

_VIEW_CASTS = {"string_view": pa.string(), "binary_view": pa.binary()}


def _no_views(t: pa.Table) -> pa.Table:
    """Cast string/binary VIEW columns to the classic layouts.

    polars exports strings as `string_view`, which older pyarrow kernels
    (cast, compare) do not handle.
    """
    for i, f in enumerate(t.schema):
        to = _VIEW_CASTS.get(str(f.type))
        if to is not None:
            t = t.set_column(i, f.name, t.column(i).cast(to))
    return t


def _module(x: object) -> str:
    return type(x).__module__.split(".")[0]


def as_table(x: object, arg: str = "data") -> pa.Table:
    """Coerce a tabular object to a `pyarrow.Table`."""
    if isinstance(x, pa.Table):
        return x
    if isinstance(x, pa.RecordBatch):
        return pa.Table.from_batches([x])
    if isinstance(x, dict):
        return pa.table(x)
    mod = _module(x)
    if mod == "pandas":
        return pa.Table.from_pandas(x, preserve_index=False)
    if mod == "polars":
        import polars as pl

        if isinstance(x, pl.LazyFrame):
            x = x.collect()
        return x.to_arrow(compat_level=pl.CompatLevel.oldest())
    if _is_dataset(x):
        return x.to_table()
    if hasattr(x, "__arrow_c_stream__"):
        return _no_views(pa.table(x))
    if hasattr(x, "to_arrow"):
        return _no_views(x.to_arrow())
    _stop("`%s` must be a table (pyarrow, polars, pandas or a dict of columns)", arg)


def _is_dataset(x: object) -> bool:
    try:
        import pyarrow.dataset as ds
    except ImportError:  # pragma: no cover
        return False
    return isinstance(x, ds.Dataset)


@dataclass(frozen=True)
class Backend:
    """What a data argument is, and whether it is lazy."""

    kind: str
    lazy: bool


def backend_of(x: object, arg: str = "data") -> Backend:
    """Classify a data argument (R: `.ms_require_backend()`)."""
    if isinstance(x, (pa.Table, pa.RecordBatch)):
        return Backend("arrow", False)
    if isinstance(x, dict):
        return Backend("dict", False)
    if _is_dataset(x):
        return Backend("dataset", True)
    mod = _module(x)
    if mod == "pandas":
        return Backend("pandas", False)
    if mod == "polars":
        import polars as pl

        if isinstance(x, pl.LazyFrame):
            return Backend("polars_lazy", True)
        return Backend("polars", False)
    if hasattr(x, "__arrow_c_stream__") or hasattr(x, "to_arrow"):
        return Backend("arrow", False)
    _stop("`%s` must be a table (pyarrow, polars, pandas or a dict of columns), "
          "or a pyarrow Dataset or polars LazyFrame", arg)


def schema_of(x: object, bk: Backend) -> pa.Schema:
    """The column names and types, without scanning a lazy input."""
    if bk.kind == "dataset":
        return x.schema
    if bk.kind == "polars_lazy":
        return as_table(x.head(0)).schema
    return as_table(x).schema


def scan(x: object, bk: Backend, columns: Sequence[str] | None = None,
         filter: pc.Expression | None = None) -> pa.Table:
    """Materialise the needed columns (and rows) of a data argument."""
    cols = None if columns is None else list(dict.fromkeys(columns))
    if bk.kind == "dataset":
        return _no_views(x.to_table(columns=cols, filter=filter))
    if bk.kind == "polars_lazy":
        t = as_table((x.select(cols) if cols is not None else x).collect())
    else:
        t = as_table(x)
        if cols is not None:
            t = t.select(cols)
    if filter is not None:
        t = t.filter(filter)
    return t


def restore(t: pa.Table, bk: Backend, collect: bool | None = None) -> object:
    """Return a result in the caller's type (R: `.ms_restore()`)."""
    if bk.kind == "pandas":
        return t.to_pandas()
    if bk.kind in ("polars", "polars_lazy"):
        import polars as pl

        out = pl.from_arrow(t)
        if bk.kind == "polars_lazy" and not collect:
            return out.lazy()
        return out
    return t


def chunks(values: Sequence[object], size: int) -> list[list[object]]:
    """Consecutive chunks of at most `size` values (R: `.ms_chunks()`)."""
    size = max(1, int(size))
    values = list(values)
    return [values[i:i + size] for i in range(0, len(values), size)]


def distinct_rows(t: pa.Table, cols: Sequence[str]) -> pa.Table:
    """Distinct combinations of `cols`, in first-appearance order."""
    cols = list(cols)
    if not cols:
        return pa.table({})
    sub = t.select(cols).append_column(
        "__ms_i", pa.array(np.arange(t.num_rows, dtype=np.int64)))
    g = sub.group_by(cols, use_threads=True).aggregate([("__ms_i", "min")])
    g = g.sort_by("__ms_i_min")
    return g.select(cols)


def bind_rows(parts: Sequence[pa.Table]) -> pa.Table:
    """Row-bind tables, unifying schemas (R: `.ms_bind_rows()`)."""
    parts = [p for p in parts if p is not None]
    if not parts:
        return pa.table({})
    try:
        return pa.concat_tables(parts, promote_options="permissive")
    except TypeError:  # pyarrow < 14 spelling
        return pa.concat_tables(parts, promote=True)
