"""Aliases -- alternative labels for members, and strict matching (port of
R/aliases.R).

A long table keyed by (frame, unit): one row per alternative spelling a member
is known by. `scale_match()` resolves labels against member names and aliases
EXACTLY (case-insensitive) and reports ambiguity rather than guessing.
"""
from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import pyarrow as pa
import pyarrow.compute as pc

from ._utils import _preview, _stop
from .attributes import _as_list, _keys, _normalised, _replace, _unique, _with_column
from .scale_class import (
    NestedScale,
    _check_frame,
    _check_scale,
    _nav_levels,
    scale_units,
)

MATCH_SCHEMA = pa.schema([(c, pa.string()) for c in
                          ("label", "frame", "unit", "method", "candidates")])


def attach_aliases_scale(x: NestedScale, aliases: Any,
                         source: str | None = None) -> NestedScale:
    """Append alias rows; an existing (alias, frame, unit, source) row is an
    error."""
    _check_scale(x)
    new = _with_column(aliases, "aliases", "source", source)
    new = _normalised(x, aliases=new).aliases
    old = x.aliases
    cols = ("alias", "frame", "unit", "source")
    k_old = set(_keys(old, cols))
    hit = [k[0] for k in _keys(new, cols) if k in k_old]
    if hit:
        _stop("alias row(s) already present: %s", _preview(_unique(hit)))
    return _replace(x, aliases=pa.concat_tables([old, new]))


def scale_aliases(x: NestedScale, frame: str | None = None,
                  source: str | Sequence[str] | None = None) -> pa.Table:
    """The alias rows, optionally of one frame and/or some sources."""
    _check_scale(x)
    al = x.aliases
    if frame is not None:
        _check_frame(x, frame)
        al = al.filter(pc.equal(al["frame"], frame))
    if source is not None:
        al = al.filter(pc.is_in(al["source"], pa.array(_as_list(source), pa.string())))
    return al


def scale_match(x: NestedScale, labels: str | Sequence[str], frame: str | None = None,
                source: str | Sequence[str] | None = None) -> pa.Table:
    """Resolve labels to (frame, unit): exact member names first, then aliases,
    case-insensitively. `method` is "exact", "alias", "ambiguous" (with the
    `candidates`) or "none"."""
    _check_scale(x)
    if not (isinstance(labels, str) or all(isinstance(z, str) or z is None
                                            for z in labels)):
        _stop("`labels` must be character")
    labels = _as_list(labels)
    levels = list(_nav_levels(x))
    if frame is not None:
        _check_frame(x, frame)
        levels = [frame]
    names_tbl = [(f, u) for f in levels for u in scale_units(x, f)]
    al = [r for r in scale_aliases(x, source=source).to_pylist()
          if r["frame"] in levels]

    def one(lab: str | None) -> dict:
        out = {"label": lab, "frame": None, "unit": None, "method": "none",
               "candidates": None}
        if lab is None:
            return out
        key = lab.strip(" \t\r\n").lower()
        hit = [(f, u) for f, u in names_tbl if u.lower() == key]
        method = "exact"
        if not hit:
            hit = _unique((r["frame"], r["unit"]) for r in al
                          if r["alias"].lower() == key)
            method = "alias"
        if not hit:
            return out
        if len(hit) > 1:
            out.update(method="ambiguous",
                       candidates="; ".join("%s/%s" % h for h in hit))
            return out
        out.update(frame=hit[0][0], unit=hit[0][1], method=method)
        return out

    return pa.Table.from_pylist([one(lab) for lab in labels], schema=MATCH_SCHEMA)
