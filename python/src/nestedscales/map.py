"""The crosswalk through the atom layer (port of R/map.R).

Every conversion is `source -> ATOMS -> target`, collapsed into one table: one row
per pair of overlapping units, carrying the counts and weights each rule
needs. Recast is a join against this table plus one grouped aggregation.

The adapter seam is `scale_atom_pairs()`: a dimension supplies the atom-level
(from, to, w) correspondence, and everything downstream is shared. A
dimension whose atoms are generated rather than enumerated (time) overrides
it and may carry extra identifier columns through `by=`.

`source` is a reserved word in Python, so the argument is spelled `source`.
"""
from __future__ import annotations

import functools
from collections.abc import Sequence

import pyarrow as pa
import pyarrow.compute as pc

from ._backend import as_table
from ._utils import _as_str_tuple, _preview, _stop, _warn
from .scale_class import (
    NestedScale,
    _check_frame,
    _check_scale,
    _resolve_weight,
    _scale_name,
    _strings,
    scale_key,
    scale_vocab,
    scale_weights,
)

_MAP_REGISTRY: dict[str, pa.Table] = {}
_MAP_STATS = ["n_from", "n_overlap", "w", "w_from"]


@functools.singledispatch
def scale_atom_pairs(x: NestedScale, source: str, target: str,
                     weight: str | None = None, **kwargs: object) -> pa.Table:
    """Atom-level correspondence between two frames: columns `source`, `target`, `w`.

    The seam a dimension package overrides (`scale_atom_pairs.register`) when
    its atom layer is generated; extra identifier columns must be named in the
    caller's `by`.
    """
    _check_scale(x)
    lt = x.leaftable
    wcol = _map_weight(x, weight)
    w = (pa.array([1.0] * lt.num_rows) if wcol is None
         else pc.cast(lt[wcol], pa.float64()))
    return pa.table({"source": pa.array(_strings(lt, source), pa.string()),
                     "target": pa.array(_strings(lt, target), pa.string()),
                     "w": w})


def scale_map(x: NestedScale, source: str, target: str, weight: str | None = None,
              by: Sequence[str] = (), **kwargs: object) -> pa.Table:
    """Crosswalk between two frames of a scale.

    One row per pair of overlapping units with `n_from` (atoms in the `source`
    unit), `n_overlap` (atoms shared), `w` (weight of the overlap) and
    `w_from` (full weight of the `source` unit); `w / w_from` is the split share
    of `sum` disaggregation. The label columns are named by the frames; a
    null target marks atoms `target` does not cover. A registered map is returned
    as-is.
    """
    if isinstance(source, NestedScale) or isinstance(target, NestedScale):
        _stop("`source` and `target` are frame names of `x`; for the map between two "
              "scales use `scale_map_between()`")
    _check_scale(x, "x")
    _check_frame(x, source, "source")
    _check_frame(x, target, "target")
    if source == target:
        v = scale_vocab(x)
        _stop('`source` and `target` are the same %s ("%s"); the map\'s label columns '
              "are named by the %s", v["frame"], source, v["frames"])
    reg = _get_scale_map(source, target, _scale_name(x, require=False))
    if reg is not None:
        return reg
    d = scale_atom_pairs(x, source, target, weight=weight, **kwargs)
    return _finish_map(d, source, target, by=list(_as_str_tuple(by)))


def scale_map_between(source: NestedScale, target: NestedScale,
                      weight: str | None = None) -> pa.Table:
    """Crosswalk between two scales through their shared atom keys.

    Label columns are named after the scales. Atoms of `source` absent from
    `target` get a null target (with a warning).
    """
    _check_scale(source, "source")
    _check_scale(target, "target")
    source_nm = _scale_name(source, arg="source")
    target_nm = _scale_name(target, arg="target")
    if source_nm == target_nm:
        _stop('`source` and `target` have the same name ("%s"); the map\'s label '
              "columns are named by the scales -- rename one", source_nm)
    reg = _get_scale_map(source_nm, target_nm)
    if reg is not None:
        return reg

    kf, kt = scale_key(source), scale_key(target)
    keys_f = _strings(source.leaftable, kf)
    keys_t = set(_strings(target.leaftable, kt))
    shared = [k for k in keys_f if k in keys_t]
    if not shared:
        keys = "`%s` keys" % kf if kf == kt else "keys"
        hint = scale_vocab(source).get("register_map", "register_scale_map_between()")
        _stop('the atom layers of "%s" and "%s" share no %s; register an explicit '
              "crosswalk with %s", source_nm, target_nm, keys, hint)
    n_miss = len(keys_f) - len(shared)
    if n_miss > 0:
        _warn('%d atom(s) of "%s" have no counterpart in "%s"; their share is '
              "uncovered (NA target)", n_miss, source_nm, target_nm)
    wcol = _map_weight(source, weight)
    lf = source.leaftable
    w = (pa.array([1.0] * lf.num_rows) if wcol is None
         else pc.cast(lf[wcol], pa.float64()))
    d = pa.table({"source": pa.array(keys_f, pa.string()),
                  "target": pa.array([k if k in keys_t else None for k in keys_f],
                                 pa.string()),
                  "w": w})
    return _finish_map(d, source_nm, target_nm)


def _map_weight(x: NestedScale, weight: str | None) -> str | None:
    """The weight column, or None for the unweighted (equal) fallback."""
    if not scale_weights(x) and weight is None:
        return None
    return _resolve_weight(x, weight)


def _finish_map(d: pa.Table, source_lab: str, target_lab: str,
                by: Sequence[str] = ()) -> pa.Table:
    """Aggregate an atom table of source/target/w (+ `by`) into the map schema."""
    by = list(by)
    miss = [c for c in ["source", "target", "w", *by] if c not in d.column_names]
    if miss:
        _stop("the atom correspondence is missing column(s): %s", _preview(miss))
    d = d.filter(pc.is_valid(d["source"]))
    if d.num_rows == 0:
        _stop("no atoms carry a code at `source`; the map would be empty")
    d = d.select([*by, "source", "target", "w"])
    d = d.set_column(d.column_names.index("w"), "w",
                     pc.fill_null(pc.cast(d["w"], pa.float64()), 0.0))
    d = d.append_column("one", pa.array([1] * d.num_rows, pa.int32()))

    grp = [*by, "source", "target"]
    m = d.group_by(grp, use_threads=True).aggregate([("one", "sum"), ("w", "sum")])
    m = m.rename_columns([{"one_sum": "n_overlap", "w_sum": "w"}.get(c, c)
                          for c in m.column_names])
    tot = m.group_by([*by, "source"], use_threads=True).aggregate(
        [("n_overlap", "sum"), ("w", "sum")])
    tot = tot.rename_columns([
        {"n_overlap_sum": "n_from", "w_sum": "w_from"}.get(c, c)
        for c in tot.column_names])
    m = m.join(tot, [*by, "source"], use_threads=True)

    # nulls sort last by default, as R's `na.last = TRUE`
    order = pc.sort_indices(m, sort_keys=[(c, "ascending") for c in grp])
    m = m.take(order).select([*grp, "n_from", "n_overlap", "w", "w_from"])
    m = m.set_column(m.column_names.index("n_from"), "n_from",
                     pc.cast(m["n_from"], pa.int32()))
    m = m.set_column(m.column_names.index("n_overlap"), "n_overlap",
                     pc.cast(m["n_overlap"], pa.int32()))
    return m.rename_columns([{"source": source_lab, "target": target_lab}.get(c, c)
                             for c in m.column_names])


# Registry --------------------------------------------------------------------

def register_scale_map(x: NestedScale | str, source: str, target: str,
                       map: object) -> str:
    """Register a direct crosswalk between two frames of one scale.

    Scoped to the scale (object or name). `map=None` removes the entry.
    Returns the registry key.
    """
    return _register_map(_map_name_of(x, "x"), _frame_label(source, "source"),
                         _frame_label(target, "target"), map)


def register_scale_map_between(source: NestedScale | str, target: NestedScale | str,
                               map: object) -> str:
    """Register a direct crosswalk between two scales (objects or names)."""
    return _register_map("", _map_name_of(source, "source"),
                         _map_name_of(target, "target"), map)


def _register_map(scope: str, source_nm: str, target_nm: str, map: object) -> str:
    key = "%s%s%s->%s" % (scope, ":" if scope else "", source_nm, target_nm)
    if map is None:
        _MAP_REGISTRY.pop(key, None)
        return key
    if isinstance(map, (str, bytes, int, float)):
        _stop("`map` must be a data.frame (see `scale_map()`) or NULL")
    t = as_table(map, "map")
    miss = [c for c in [source_nm, target_nm, *_MAP_STATS] if c not in t.column_names]
    if miss:
        _stop("`map` is missing column(s): %s", _preview(miss))
    _MAP_REGISTRY[key] = t
    return key


def _map_name_of(z: object, arg: str) -> str:
    """A scale's name, or a name given directly."""
    if isinstance(z, str) and z != "":
        return z
    _check_scale(z, arg)
    return _scale_name(z, arg=arg)


def _frame_label(z: object, arg: str) -> str:
    if not isinstance(z, str) or z == "":
        _stop("`%s` must be a single frame name", arg)
    return z


def _get_scale_map(source_nm: str, target_nm: str, scope: str = "") -> pa.Table | None:
    keys = ["%s%s%s->%s" % (scope, ":" if scope else "", source_nm, target_nm),
            "%s->%s" % (source_nm, target_nm)]
    for k in dict.fromkeys(keys):
        if k in _MAP_REGISTRY:
            return _MAP_REGISTRY[k]
    return None


def get_scale_map(x: NestedScale | str, source: str, target: str) -> pa.Table | None:
    """The map registered for two frames of `x`, or None."""
    return _get_scale_map(_frame_label(source, "source"),
                          _frame_label(target, "target"), scope=_map_name_of(x, "x"))


def get_scale_map_between(source: NestedScale | str,
                          target: NestedScale | str) -> pa.Table | None:
    """The map registered between two scales, or None."""
    return _get_scale_map(_map_name_of(source, "source"),
                          _map_name_of(target, "target"))


def list_scale_maps() -> pa.Table:
    """Registry keys, one row each (column `key`)."""
    return pa.table({"key": pa.array(sorted(_MAP_REGISTRY), pa.string())})


def clear_scale_maps(name: str | Sequence[str] | None = None) -> None:
    """Remove registered crosswalks: the named registry keys (as
    `list_scale_maps()` reports them), or, with `name=None`, all of them."""
    if name is None:
        _MAP_REGISTRY.clear()
        return
    for k in _as_str_tuple(name):
        _MAP_REGISTRY.pop(k, None)
