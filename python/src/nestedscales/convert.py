"""Unit conversion through a resolved attribute (port of R/convert.R).

`convert_scale()` multiplies (or, for a `property`, divides) value columns by
the attribute resolved for each row's code, e.g. t -> GJ with `lhv` (GJ/t),
or TJ -> kg with `ef_co2` (kg/TJ). No unit-prefix arithmetic: the units must
be the attribute's own numerator and denominator.
"""
from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import pyarrow as pa
import pyarrow.compute as pc

from ._utils import _preview, _stop
from .attributes import _as_list, _is_string, _unique, scale_attributes
from .backend import backend_of, backend_restore, backend_scan, backend_schema
from .scale_class import (
    NestedScale,
    _check_frame,
    _check_scale,
    _nav_levels,
    scale_vocab,
)


def _parse_uom(uom: str) -> tuple[str, str]:
    parts = [p.strip(" \t\r\n") for p in uom.split("/")]
    if len(parts) != 2 or any(p == "" for p in parts):
        _stop('unit of measure "%s" is not of the form "<numerator>/<denominator>" '
              '(e.g. "GJ/t")', uom)
    return parts[0], parts[1]


def _is_numeric_type(ty: pa.DataType) -> bool:
    return pa.types.is_integer(ty) or pa.types.is_floating(ty)


def convert_scale(data: Any, x: NestedScale, attribute: str, from_unit: str,
                  to_unit: str, key: str | None = None, frame: str | None = None,
                  values: str | Sequence[str] | None = None,
                  source: str | Sequence[str] | None = None,
                  na_action: str = "error", collect: bool | None = None) -> Any:
    """Convert the value columns of `data` from `from_unit` to `to_unit` with
    the attribute resolved for each code. Adds `<attribute>` (the factor used)
    and `<attribute>.origin_frame` (where it was found)."""
    if na_action not in ("error", "keep"):
        _stop('`na_action` must be "error" or "keep"')
    _check_scale(x, "x")
    v = scale_vocab(x)
    if not _is_string(attribute):
        _stop("`attribute` must be a single string")
    if not _is_string(from_unit) or not _is_string(to_unit):
        _stop("`from_unit` and `to_unit` must be single strings")
    bk = backend_of(data, "data")
    schema = backend_schema(data, bk)
    names = schema.names
    if frame is None:
        hit = [f for f in _nav_levels(x) if f in names]
        if len(hit) != 1:
            _stop("cannot infer the code %s from the data's columns (found: %s); pass "
                  "`frame=`", v["frame"], "none" if not hit else _preview(hit))
        frame = hit[0]
    _check_frame(x, frame, "frame")
    if key is None:
        key = frame
    if not _is_string(key) or key not in names:
        _stop("the data has no column named `%s`; pass `key=`", key)
    if values is None:
        values = [c for c in names
                  if c != key and _is_numeric_type(schema.field(c).type)]
        if not values:
            _stop("no numeric value columns found in `data`; specify `values=`")
    else:
        values = _as_list(values)
        bad = [c for c in values if c not in names]
        if bad:
            _stop("value column(s) not in `data`: %s", _preview(bad))

    res = scale_attributes(x, attribute, frame=frame, source=source, inherit=True)
    uom = _unique(u for u in res["unit_of_measure"].to_pylist() if u is not None)
    if not uom:
        _stop("no `%s` value resolves for any %s at %s `%s`", attribute, v["unit"],
              v["frame"], frame)
    if len(uom) > 1:
        _stop("`%s` is stored in several units of measure (%s); pass `source=`",
              attribute, ", ".join(uom))
    num, den = _parse_uom(uom[0])
    kind = _unique(k for k in res["kind"].to_pylist() if k is not None)
    kind = kind[0] if len(kind) == 1 else None
    if from_unit == den and to_unit == num:
        op = "multiply"
    elif from_unit == num and to_unit == den:
        if kind != "property":
            _stop("`%s` converts %s -> %s only; the inverse is refused because it is "
                  "a %s, not a property (see SCALE_ATTRIBUTE_KINDS)",
                  attribute, den, num, kind)
        op = "divide"
    else:
        _stop("`%s` is in %s and converts %s -> %s%s; got %s -> %s (no unit-prefix "
              "arithmetic: convert kt to t first)", attribute, uom[0], den, num,
              " (or back)" if kind == "property" else "", from_unit, to_unit)
    out_cols = (attribute, attribute + ".origin_frame")
    clash = [c for c in names if c in (*out_cols, ".ms_factor", ".ms_origin_frame")]
    if clash:
        _stop("`data` already has column(s) %s; existing columns are never "
              "overwritten", _preview(clash))

    t = backend_scan(data, bk)
    kcol = pc.cast(t[key], pa.string()).to_pylist()
    codes = _unique(c for c in kcol if c is not None)
    units = res["unit"].to_pylist()
    unknown = [c for c in codes if c not in set(units)]
    if unknown:
        _stop("code(s) in `data$%s` that are not %s of %s `%s`: %s", key, v["units"],
              v["frame"], frame, _preview(unknown))
    fac = dict(zip(units, res["value"].to_pylist(), strict=True))
    org = dict(zip(units, res["origin_frame"].to_pylist(), strict=True))
    unresolved = [c for c in codes if fac.get(c) is None]
    if unresolved and na_action == "error":
        _stop("no `%s` value resolves for %s at %s `%s`; attach one with "
              'attach_attributes_scale() or pass na_action = "keep"',
              attribute, _preview(unresolved), v["frame"], frame)
    factor = pa.array([None if k is None else fac.get(k) for k in kcol], pa.float64())
    origin = pa.array([None if k is None else org.get(k) for k in kcol], pa.string())
    fn = pc.multiply if op == "multiply" else pc.divide
    for c in values:
        t = t.set_column(t.column_names.index(c), c,
                         fn(pc.cast(t[c], pa.float64()), factor))
    t = t.append_column(out_cols[0], factor).append_column(out_cols[1], origin)
    return backend_restore(t, bk, collect=collect)
