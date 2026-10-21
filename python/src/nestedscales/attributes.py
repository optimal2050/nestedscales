"""Member attributes (port of R/attributes.R).

One long table on the scale, keyed by (frame, unit): a physical attribute (a
calorific value, a density) may sit on an atom or on any coarser member.
`scale_attributes()` resolves a value for every member of a frame by taking
the member's own entry first and otherwise walking to the nearest coarser
frame that holds one. Attributes are not weights and are never recast;
`convert_scale()` multiplies with them row by row.
"""
from __future__ import annotations

import copy
from collections.abc import Sequence
from typing import Any

import pyarrow as pa
import pyarrow.compute as pc

from ._backend import as_table
from ._utils import _preview, _stop
from .scale_class import (
    ALIAS_SCHEMA,
    ATTR_SCHEMA,
    NestedScale,
    _check_frame,
    _check_scale,
    _nav_levels,
    _strings,
    scale_units,
    scale_vocab,
)

RESOLVED_SCHEMA = pa.schema([*ATTR_SCHEMA, ("origin_frame", pa.string()),
                             ("origin_unit", pa.string())])


def _is_string(x: object) -> bool:
    return isinstance(x, str) and x != ""


def _as_list(x: object) -> list:
    if x is None:
        return []
    if isinstance(x, str):
        return [x]
    return list(x)


def _unique(it) -> list:
    return list(dict.fromkeys(it))


def _chr(z: object) -> str:
    return "NA" if z is None else str(z)


def _with_column(t: Any, arg: str, name: str, value: str | None) -> pa.Table:
    """`attributes`/`aliases` as a table, with a scalar `source=`/`kind=`
    filled in as a column."""
    t = as_table(t, arg)
    if value is not None:
        if not _is_string(value):
            _stop("`%s` must be a single string", name)
        if name in t.column_names:
            _stop("`%s` already has a `%s` column; drop `%s=`", arg, name, name)
        t = t.append_column(name, pa.array([value] * t.num_rows, pa.string()))
    return t


def _replace(x: NestedScale, **fields: Any) -> NestedScale:
    """A copy of `x` with `fields` replaced, validated as R's `prop<-` does."""
    out = _normalised(x, **fields)
    out.__post_init__()
    return out


def _normalised(x: NestedScale, **fields: Any) -> NestedScale:
    """A copy of `x` with `fields` replaced and coerced, not yet validated
    (R's `.as_attributes()` / `.as_aliases()`)."""
    out = copy.copy(x)
    for k, v in fields.items():
        object.__setattr__(out, k, v)
    out._normalise()
    return out


def _keys(t: pa.Table, cols: Sequence[str]) -> list[tuple]:
    return list(zip(*(t[c].to_pylist() for c in cols), strict=True))


def attach_attributes_scale(x: NestedScale, attributes: Any, source: str | None = None,
                            kind: str | None = None) -> NestedScale:
    """Append attribute rows. An existing (frame, unit, attribute, source) row
    is never overwritten: attach a competing value under another `source`."""
    _check_scale(x)
    new = _with_column(attributes, "attributes", "source", source)
    new = _with_column(new, "attributes", "kind", kind)
    new = _normalised(x, attributes=new).attributes  # columns and types only
    old = x.attributes
    cols = ("frame", "unit", "attribute", "source")
    k_old = set(_keys(old, cols))
    hit = [k for k in _keys(new, cols) if k in k_old]
    if hit:
        _stop("attribute row(s) already present (never overwritten): %s; attach "
              "under another `source`",
              _preview("%s/%s:%s@%s" % tuple(_chr(z) for z in k) for k in hit))
    return _replace(x, attributes=pa.concat_tables([old, new]))  # validated whole


def scale_attributes(x: NestedScale, attribute: str | Sequence[str] | None = None,
                     frame: str | None = None,
                     source: str | Sequence[str] | None = None,
                     inherit: bool = True) -> pa.Table:
    """The stored attribute rows, or with `frame=` one row per member of that
    frame and attribute, resolved along the hierarchy (`origin_frame` and
    `origin_unit` say where each value was found)."""
    _check_scale(x)
    at = x.attributes
    v = scale_vocab(x)
    if attribute is not None:
        if not (isinstance(attribute, str)
                or all(isinstance(a, str) for a in attribute)):
            _stop("`attribute` must be character")
        attribute = _as_list(attribute)
        stored = _unique(at["attribute"].to_pylist())
        unknown = _unique(a for a in attribute if a not in stored)
        if unknown:
            _stop("attribute(s) not stored on this %s: %s (stored: %s)", v["object"],
                  _preview(unknown), ", ".join(stored) if stored else "<none>")
        at = at.filter(pc.is_in(at["attribute"], pa.array(attribute, pa.string())))
    if source is not None:
        if not (isinstance(source, str) or all(isinstance(s, str) for s in source)):
            _stop("`source` must be character")
        source = _as_list(source)
        stored = set(at["source"].to_pylist())
        unknown = _unique(s for s in source if s not in stored)
        if unknown:
            _stop("source(s) not stored on this %s: %s", v["object"], _preview(unknown))
        at = at.filter(pc.is_in(at["source"], pa.array(source, pa.string())))
    if frame is None:
        return at
    _check_frame(x, frame)
    return _resolve_attributes(x, at, frame, inherit=bool(inherit))


def _ancestry_to(x: NestedScale, frame: str) -> dict[tuple, list]:
    """(parent_frame, child) -> parents, for `frame` -- including the key
    level, which `scale_ancestry()` does not list."""
    from .navigate import scale_ancestry

    out: dict[tuple, list] = {}
    if frame in x.frames:
        for r in scale_ancestry(x).to_pylist():
            if r["child_frame"] == frame:
                out.setdefault((r["parent_frame"], r["child"]), []).append(r["parent"])
        return out
    lt = x.leaftable
    child = _strings(lt, frame)
    for f in x.frames:
        for p, c in zip(_strings(lt, f), child, strict=True):
            if p is not None and c is not None:
                lst = out.setdefault((f, c), [])
                if p not in lst:
                    lst.append(p)
    return out


def _resolve_attributes(x: NestedScale, at: pa.Table, frame: str,
                        inherit: bool) -> pa.Table:
    frames = list(x.frames)
    units = list(scale_units(x, frame))
    v = scale_vocab(x)
    rows = at.to_pylist()
    attrs = _unique(r["attribute"] for r in rows)
    coarser = (list(reversed(frames[:frames.index(frame)])) if frame in frames
               else list(reversed(frames)))
    parents_of = _ancestry_to(x, frame) if (inherit and coarser) else {}
    by_key: dict[tuple, list] = {}
    for r in rows:
        by_key.setdefault((r["frame"], r["unit"], r["attribute"]), []).append(r)

    def pick(a: str, u: str) -> dict:
        hit = by_key.get((frame, u, a), [])
        origin = (frame, u)
        if not hit and inherit:
            for cf in coarser:
                parents = _unique(parents_of.get((cf, u), []))
                if not parents:
                    continue
                cand = [r for r in rows if r["attribute"] == a and r["frame"] == cf
                        and r["unit"] in parents]
                if not cand:
                    continue
                if len(parents) > 1:
                    _stop("inheritance of `%s` is ambiguous for `%s` at %s `%s`: it "
                          "spans %s at %s `%s`, which holds the attribute; store a "
                          "value at `%s` or pass a nesting %s",
                          a, u, v["frame"], frame, _preview(parents, 5), v["frame"],
                          cf, frame, v["frame"])
                hit = cand
                origin = (cf, parents[0])
                break
        if len(hit) > 1:
            _stop("`%s` for `%s` at %s `%s` is published by several sources (%s); "
                  "pass `source=`", a, origin[1], v["frame"], origin[0],
                  ", ".join(_unique(r["source"] for r in hit)))
        if not hit:
            out = dict.fromkeys(ATTR_SCHEMA.names)
            out.update(frame=frame, unit=u, attribute=a)
            origin = (None, None)
        else:
            out = dict(hit[0], frame=frame, unit=u)
        out["origin_frame"], out["origin_unit"] = origin
        return out

    return pa.Table.from_pylist([pick(a, u) for a in attrs for u in units],
                                schema=RESOLVED_SCHEMA)


__all__ = ["attach_attributes_scale", "scale_attributes", "RESOLVED_SCHEMA",
           "ALIAS_SCHEMA", "_nav_levels"]
