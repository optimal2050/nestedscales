"""The data-backend layer, public for dimension packages (R: the `.ms_*`
helpers, to be renamed `backend_*` there too).

A dimension package built on nestedscales -- the Python ports of timescales
and geoscales -- uses these to accept the same inputs as the core verbs and
to hand results back in the caller's type.
"""
from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import pyarrow as pa
import pyarrow.compute as pc

from . import _backend
from ._backend import Backend


def backend_of(data: Any, arg: str = "data") -> Backend:
    """Classify a data argument; error when it is not a supported table.

    R: `.ms_backend()` / `.ms_require_backend()`.
    """
    return _backend.backend_of(data, arg)


def backend_is_lazy(backend: Backend) -> bool:
    """Is this a lazy backend (pyarrow Dataset, polars LazyFrame)?

    R: `.ms_is_lazy()`.
    """
    return backend.lazy


def backend_schema(data: Any, backend: Backend | None = None) -> pa.Schema:
    """Column names and types, without scanning a lazy input.

    R: `.ms_schema()`.
    """
    return _backend.schema_of(data, backend or backend_of(data))


def backend_scan(data: Any, backend: Backend | None = None,
                 columns: Sequence[str] | None = None,
                 filter: pc.Expression | None = None) -> pa.Table:
    """Materialise the needed columns (and rows) of a data argument, pushing
    the projection and filter into the scan of a lazy input.

    R: `.ms_lazy()` followed by `.ms_pull()`.
    """
    return _backend.scan(data, backend or backend_of(data), columns, filter)


def backend_pull(data: Any) -> pa.Table:
    """Any supported table, collected into a `pyarrow.Table`.

    R: `.ms_pull()`.
    """
    return _backend.as_table(data)


def backend_restore(table: pa.Table, backend: Backend,
                    collect: bool | None = None) -> Any:
    """A result in the caller's type: pandas, polars, a LazyFrame (unless
    `collect`), or a `pyarrow.Table`.

    R: `.ms_restore()`.
    """
    return _backend.restore(table, backend, collect)


def backend_bind_rows(parts: Sequence[pa.Table]) -> pa.Table:
    """Row-bind tables, unifying their schemas. R: `.ms_bind_rows()`."""
    return _backend.bind_rows(parts)


def backend_distinct(table: pa.Table, columns: Sequence[str]) -> pa.Table:
    """Distinct combinations of `columns` in first-appearance order.

    Python only: R gets this from `dplyr::distinct()`.
    """
    return _backend.distinct_rows(table, columns)


__all__ = ["Backend", "backend_bind_rows", "backend_distinct", "backend_is_lazy",
           "backend_of", "backend_pull", "backend_restore", "backend_scan",
           "backend_schema"]
