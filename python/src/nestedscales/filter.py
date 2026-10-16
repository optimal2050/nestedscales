"""Subsetting and collapsing a NestedScale (port of R/filter.R).

A genuine subset is a SAMPLE and is book-kept as one: it knows what fraction
of its root parent it carries and can never impersonate that parent.
"""
from __future__ import annotations

import copy
import hashlib
from collections.abc import Sequence
from typing import Any

import pyarrow as pa
import pyarrow.compute as pc

from ._utils import _as_str_tuple, _preview, _stop
from .scale_class import (
    NestedScale,
    _check_frame,
    _check_scale,
    _finite_sum,
    _resolve_weight,
    _strings,
    scale_key,
    scale_payload_slice,
    scale_vocab,
    scale_weights,
)
from .scale_construct import scale_from_leaftable


def _sample_meta(x: NestedScale, meta: dict, kept: pa.Table, tag: str) -> dict:
    """Coverage of the ROOT parent, parent totals, and the mangled name."""
    wts = scale_weights(x)
    lt = x.leaftable
    totals = meta.get("parent_totals")
    if totals is None:
        totals = {w: _finite_sum(lt[w].to_pylist()) for w in wts}
    cov = {w: _finite_sum(kept[w].to_pylist()) / totals[w] for w in wts}
    base = meta.get("parent_name") or meta.get("name") or ""
    meta = dict(meta)
    meta.update(parent_totals=dict(totals), coverage=cov, parent_name=base,
                name=base + tag)
    return meta


def _rebuild(x: NestedScale, keep: Sequence[int], fr: Sequence[str],
             drop_empty_frames: bool = False, meta: dict | None = None) -> NestedScale:
    """A copy of `x` restricted to leaftable rows `keep`.

    Copying `x` itself keeps the concrete class and any subclass fields; the
    payload hook slices per-atom payloads before the single validation.
    """
    lt = x.leaftable.take(pa.array(list(keep), pa.int64()))
    members = {}
    for f in fr:
        seen = {v for v in _strings(lt, f) if v is not None}
        members[f] = tuple(c for c in x.members[f] if c in seen)
    fr = list(fr)
    if drop_empty_frames:
        fr = [f for f in fr if members[f]]
        if not fr:
            _stop("every frame would be empty")
        members = {f: members[f] for f in fr}
    else:
        empty = [f for f in fr if not members[f]]
        if empty:
            _stop("frame(s) left with no codes: %s; pass drop_empty_frames = TRUE",
                  _preview(empty))
    out = copy.copy(x)
    for k, v in (("leaftable", lt), ("frames", tuple(fr)), ("members", members),
                 ("meta", dict(x.meta if meta is None else meta))):
        object.__setattr__(out, k, v)
    out = scale_payload_slice(out, list(keep))
    out.__post_init__()
    return out


def _sample_id(codes: Sequence[str]) -> str:
    """Identify a sample by its codes, hashing when they are too long to list.

    R hashes with `rlang::hash()`, which is not reproducible outside R, so a
    long sample's name differs between bindings.
    """
    if sum(len(c) for c in codes) + len(codes) <= 24:
        return "+".join(codes)
    h = hashlib.blake2b("\n".join(sorted(codes)).encode(), digest_size=4)
    return "%d~%s" % (len(codes), h.hexdigest())


def filter_scale(x: NestedScale, frame: str, unit: str | Sequence[str],
                 drop_empty_frames: bool = False) -> NestedScale:
    """Keep only the atoms belonging to `unit` at `frame`.

    A real subset records `coverage` (per weight, of the root parent),
    `parent_totals`, `parent_name`, and is renamed `"parent[frame:codes]"`.
    A filter that keeps every atom is a no-op.
    """
    _check_scale(x)
    _check_frame(x, frame)
    unit = _as_str_tuple(unit)
    known = set(x.members.get(frame, ()))
    unknown = [u for u in dict.fromkeys(unit) if u not in known]
    if unknown:
        _stop("code(s) not found at %s `%s`: %s", scale_vocab(x)["frame"], frame,
              _preview(unknown))
    col = _strings(x.leaftable, frame)
    want = set(unit)
    keep = [i for i, v in enumerate(col) if v in want]
    if not keep:
        _stop("no atoms remain after filtering")
    meta = dict(x.meta)
    if len(keep) < x.leaftable.num_rows:
        codes = list(dict.fromkeys(col[i] for i in keep))
        meta = _sample_meta(x, meta, x.leaftable.take(pa.array(keep)),
                            "[%s:%s]" % (frame, _sample_id(codes)))
    return _rebuild(x, keep, x.frames, drop_empty_frames, meta=meta)


def prune_scale(x: NestedScale, frame: str) -> NestedScale:
    """Collapse to a coarser frame: `frame` becomes the atom layer.

    Weights are summed over the collapsed atoms; the result is renamed
    `"name@frame"`. Atoms with no code at `frame` are dropped, and the loss
    shows in `coverage`.
    """
    _check_scale(x)
    _check_frame(x, frame)
    fr = list(x.frames)
    if frame not in fr:
        return x
    keep_fr = fr[:fr.index(frame) + 1]
    lt0 = x.leaftable
    covered = pc.is_valid(lt0[frame])
    lt = lt0.filter(covered)
    if lt.num_rows == 0:
        _stop("no atoms have a code at %s `%s`", scale_vocab(x)["frame"], frame)

    wts = scale_weights(x)
    rows = list(zip(*(_strings(lt, f) for f in keep_fr), strict=True))
    first: dict = {}
    totals: dict = {w: {} for w in wts}
    wvals = {w: lt[w].to_pylist() for w in wts}
    for i, r in enumerate(rows):
        first.setdefault(r, i)
        for w in wts:
            z = wvals[w][i]
            ok = z is not None and z == z
            totals[w][r] = totals[w].get(r, 0.0) + (float(z) if ok else 0.0)
    groups = list(first)
    akey = scale_key(x)
    cols: dict[str, Any] = {f: pa.array([g[j] for g in groups], pa.string())
                            for j, f in enumerate(keep_fr)}
    for w in wts:
        cols[w] = pa.array([totals[w][g] for g in groups], pa.float64())
    cols[akey] = cols[frame]
    out = pa.table(cols)

    meta = x.meta
    new_meta = dict(meta)
    if not pc.all(covered).as_py():
        new_meta = _sample_meta(x, new_meta, lt, "")
    new_meta["parent_name"] = meta.get("name") or ""
    new_meta["name"] = "%s@%s" % (meta.get("name") or "", frame)
    s = scale_from_leaftable(out, frames=keep_fr, key=akey, weights=wts,
                             default_weight=meta.get("default_weight"),
                             name=new_meta["name"], desc=meta.get("desc") or "")
    # R's modifyList(): a NULL entry removes the field
    for k in ("weights", "default_weight"):
        if s.meta.get(k) is None:
            new_meta.pop(k, None)
        else:
            new_meta[k] = s.meta[k]
    return NestedScale(leaftable=s.leaftable, frames=s.frames, members=s.members,
                       key=s.key, meta=new_meta)


def scale_share(x: NestedScale, frame: str, weight: str | None = None,
                within: str | None = None) -> pa.Table:
    """Weight shares of the units of `frame`, over the whole scale or within
    each unit of the coarser frame `within`."""
    _check_scale(x)
    _check_frame(x, frame)
    weight = _resolve_weight(x, weight)
    lt = x.leaftable
    units = _strings(lt, frame)
    w = [0.0 if z is None or z != z else float(z) for z in lt[weight].to_pylist()]
    if within is None:
        grp = [""] * lt.num_rows
    else:
        _check_frame(x, within, "within")
        grp = _strings(lt, within)
    agg: dict = {}
    for u, g, z in zip(units, grp, w, strict=True):
        if u is None or g is None:  # R's aggregate() drops NA groups
            continue
        agg[(u, g)] = agg.get((u, g), 0.0) + z
    gtot: dict = {}
    for (_, g), z in agg.items():
        gtot[g] = gtot.get(g, 0.0) + z
    order = {c: i for i, c in enumerate(x.members[frame])}
    keys = sorted(agg, key=lambda k: (order[k[0]], k[1]))
    cols: dict[str, Any] = {frame: pa.array([k[0] for k in keys], pa.string())}
    if within is not None:
        cols[within] = pa.array([k[1] for k in keys], pa.string())
    cols[weight] = pa.array([agg[k] for k in keys], pa.float64())
    cols["share"] = pa.array([agg[k] / gtot[k[1]] for k in keys], pa.float64())
    return pa.table(cols)
