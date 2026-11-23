"""Long table <-> dense array (port of R/array.R, single-scale part).

The long table is canonical; the array is a view, the shape optimisation
models think in. The size is checked before anything is allocated. Axis
labels are the scale's members (`scale_members()`), in that order.
"""
from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import numpy as np
import pyarrow as pa
import pyarrow.compute as pc

from ._backend import backend_of, scan, schema_of
from ._utils import _preview, _stop
from .scale_class import NestedScale, _check_scale, scale_leaf_column, scale_members


def _axis(x: NestedScale, frames: Sequence[str] | str | None,
          cols: Sequence[str] | None = None) -> tuple[str, list[str]]:
    _check_scale(x)
    fr = frames if isinstance(frames, str) or frames is None else frames[0]
    cand = scale_leaf_column(x) if fr is None else fr
    if cols is not None and cand not in cols and scale_leaf_column(x) in cols:
        cand = scale_leaf_column(x)
    return cand, scale_members(x) if fr is None else scale_members(x, fr)


def as_scale_array(data: Any, x: NestedScale, value: str | None = None,
                   frames: Sequence[str] | str | None = None, fill: float = np.nan,
                   limit: float = 1e7) -> np.ndarray:
    """A dense numpy array over the members of one frame (default: leaves)."""
    bk = backend_of(data, "data")
    schema = schema_of(data, bk)
    key, members = _axis(x, frames, schema.names)
    n = len(members)
    if n > limit:
        _stop("a dense array of this shape needs %s cells (%s), above `limit`. The "
              "long table is the form that stays workable at this size.",
              format(n, ","), "%s: %d" % (key, n))
    d = scan(data, bk)
    if key not in d.column_names:
        _stop("the data has no column(s) %s (one key column per axis)", key)
    if value is None:
        cand = [c for c in d.column_names if c != key and (
            pa.types.is_integer(d.schema.field(c).type)
            or pa.types.is_floating(d.schema.field(c).type))]
        if len(cand) != 1:
            _stop("cannot infer the value column (found: %s); pass `value=`",
                  "none" if not cand else _preview(cand))
        value = cand[0]
    if value not in d.column_names:
        _stop("`value` column `%s` is not in the data", value)
    pos = {u: i for i, u in enumerate(members)}
    codes = d[key].cast(pa.string()).to_pylist()
    bad = list(dict.fromkeys(c for c in codes if c not in pos))
    if bad:
        _stop("column `%s` holds code(s) that are not members of axis `%s`: %s",
              key, key, _preview(bad))
    a = np.full(n, fill, dtype=float)
    vals = d[value].to_pylist()
    for c, z in zip(codes, vals, strict=True):
        a[pos[c]] = np.nan if z is None else z
    return a


def as_scale_table(a: Any, x: NestedScale, value: str = "value",
                   frames: Sequence[str] | str | None = None,
                   drop_na: bool = True) -> pa.Table:
    """The long table of a dense array over one frame's members."""
    key, members = _axis(x, frames)
    a = np.asarray(a, dtype=float)
    if a.ndim != 1 or a.shape[0] != len(members):
        _stop("the array is %s but this scale describes %d",
              " x ".join(str(s) for s in a.shape), len(members))
    t = pa.table({key: pa.array(members, pa.string()), value: pa.array(a)})
    if drop_na:
        t = t.filter(pc.invert(pc.is_nan(t[value])))
    return t
