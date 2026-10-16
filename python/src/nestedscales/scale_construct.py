"""Construction (port of R/scale-construct.R)."""
from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any

import pyarrow as pa
import pyarrow.compute as pc

from ._backend import as_table
from ._utils import _as_str_tuple, _preview, _stop, _warn
from .frames import RESERVED_COLS
from .scale_class import NestedScale, _is_numeric, _strings


def _blank_to_na(col: pa.ChunkedArray) -> pa.ChunkedArray:
    """Character, with blank or whitespace-only strings as null.

    Real scale tables use "" and NA interchangeably for "no code at this
    frame". Non-blank values are kept untrimmed.
    """
    col = pc.cast(col, pa.string())
    blank = pc.equal(pc.utf8_trim_whitespace(col), "")
    return pc.if_else(pc.fill_null(blank, False), pa.scalar(None, pa.string()), col)


def _nests_in(lt: pa.Table, fine: str, coarse: str) -> bool:
    """Every code of `fine` sits inside exactly one code of `coarse`."""
    if lt[fine].null_count or lt[coarse].null_count:
        return False
    seen: dict = {}
    for f, c in zip(_strings(lt, fine), _strings(lt, coarse), strict=True):
        if seen.setdefault(f, c) != c:
            return False
    return True


def scale_from_leaftable(
    leaftable: Any,
    frames: str | Sequence[str],
    key: str | None = None,
    weights: str | Sequence[str] | None = None,
    default_weight: str | None = None,
    members: Mapping[str, Sequence[str]] | None = None,
    name: str = "",
    desc: str = "",
    **meta: Any,
) -> NestedScale:
    """Build a NestedScale from a flat table of atoms.

    `leaftable` has one row per atom, one column per name in `frames`
    (coarsest first) and optionally numeric weight columns. Blank strings in
    frame columns become null: that atom has no code at that frame.

    `key` defaults to `"unit"` when that column exists, else the finest frame.
    `weights` defaults to every numeric column that is neither a frame, the
    key, nor a reserved name. `members` defaults to first-appearance order.
    Extra keyword arguments are merged into `meta` (e.g. `source`, `labels`).
    """
    lt = as_table(leaftable, "leaftable")
    frames = _as_str_tuple(frames)
    if len(frames) == 0 or not all(isinstance(f, str) for f in frames):
        _stop("`frames` must be a non-empty character vector")
    missing = [f for f in frames if f not in lt.column_names]
    if missing:
        _stop("`leaftable` is missing frame column(s): %s", _preview(missing))

    # Frame columns to character, blanks to null
    for f in frames:
        lt = lt.set_column(lt.column_names.index(f), f, _blank_to_na(lt[f]))

    # Atom key
    if key is None:
        key = "unit" if "unit" in lt.column_names else frames[-1]
    if not isinstance(key, str) or key == "":
        _stop("`key` must be a single non-empty string")
    if key not in lt.column_names:
        _stop('`key` column "%s" not found in `leaftable`', key)
    if key not in frames:
        lt = lt.set_column(lt.column_names.index(key), key,
                           pc.cast(lt[key], pa.string()))
    if any(u is None or u == "" for u in lt[key].to_pylist()):
        _stop('the atom key column "%s" has missing or empty values; every atom '
              "needs an identifier", key)

    # Weights
    if weights is None:
        skip = {*frames, *RESERVED_COLS, key}
        weights = [c for c in lt.column_names
                   if c not in skip and _is_numeric(lt, c)]
    weights = list(_as_str_tuple(weights))
    bad = [w for w in weights if w not in lt.column_names]
    if bad:
        _stop("weight column(s) not found in `leaftable`: %s", _preview(bad))
    if default_weight is None and weights:
        default_weight = weights[0]

    # Members
    if members is None:
        members = {f: [v for v in dict.fromkeys(_strings(lt, f)) if v is not None]
                   for f in frames}
    empty = [f for f in frames if len(_as_str_tuple(members.get(f))) == 0]
    if empty:
        _stop("frame(s) with no codes at all: %s", _preview(empty))

    # Coarse-to-fine ordering: tests CONTAINMENT, not code counts. Only the
    # reverse containment -- each coarse code inside one fine code -- means the
    # list is upside down; cross-cutting frames nest in neither direction.
    inverted = [b for a, b in zip(frames[:-1], frames[1:], strict=True)
                if _nests_in(lt, a, b) and not _nests_in(lt, b, a)]
    if inverted:
        _warn("`frames` should be ordered coarsest first, but %s CONTAINS the "
              "frame before it. Aggregation direction is taken from this order.",
              _preview(inverted))

    return NestedScale(
        leaftable=lt, frames=frames, members=dict(members), key=key,
        meta={"name": name, "desc": desc, "weights": weights,
              "default_weight": default_weight, **meta})


def scale_example() -> NestedScale:
    """A small example scale with three awkward real-world features.

    * a code ("G1") reused at two frames, so lookups must name the frame;
    * a non-nesting pair -- group "GB" draws units from two classes;
    * a unit ("OTH") with no code at any coarser frame.
    """
    df = {
        "sector": ["P", "P", "P", "P", "S", "S", None],
        "class": ["G1", "G1", "G2", "G2", "S1", "S1", None],
        "group": ["G1", "G1", "GB", "GB", "GB", "GC", None],
        "unit": ["U1", "U2", "U3", "U4", "U5", "U6", "OTH"],
        "size": [100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 1000.0],
        "count": [10.0, 90.0, 30.0, 70.0, 50.0, 50.0, 0.0],
    }
    return scale_from_leaftable(
        pa.table(df), frames=["sector", "class", "group", "unit"],
        name="example",
        desc="Synthetic example: reused code, non-nesting frame pair, and an "
             "unassigned atom")


def scale_example2() -> NestedScale:
    """A second small, well-behaved example scale (frames era/period)."""
    df = {
        "era": ["E1", "E1", "E2", "E2"],
        "period": ["p1", "p2", "p3", "p4"],
        "span": [1.0, 3.0, 2.0, 4.0],
    }
    return scale_from_leaftable(
        pa.table(df), frames=["era", "period"], name="example2",
        desc="Synthetic second dimension, for product examples")
