"""The crosswalk through the atom layer (port of R/map.R).

Every conversion is `from -> ATOMS -> to`, collapsed into one table: one row
per pair of overlapping units, carrying the counts and weights each rule
needs. Recast is a join against this table plus one grouped aggregation.

The adapter seam is `scale_atom_pairs()`: a dimension supplies the atom-level
(from, to, w) correspondence, and everything downstream is shared. A
dimension whose atoms are generated rather than enumerated (time) overrides
it and may carry extra identifier columns through `by=`.

`from` is a reserved word in Python, so the argument is spelled `from_`.
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
def scale_atom_pairs(x: NestedScale, from_: str, to: str,
                     weight: str | None = None, **kwargs: object) -> pa.Table:
    """Atom-level correspondence between two frames: columns `from`, `to`, `w`.

    The seam a dimension package overrides (`scale_atom_pairs.register`) when
    its atom layer is generated; extra identifier columns must be named in the
    caller's `by`.
    """
    _check_scale(x)
    lt = x.leaftable
    wcol = _map_weight(x, weight)
    w = (pa.array([1.0] * lt.num_rows) if wcol is None
         else pc.cast(lt[wcol], pa.float64()))
    return pa.table({"from": pa.array(_strings(lt, from_), pa.string()),
                     "to": pa.array(_strings(lt, to), pa.string()),
                     "w": w})


def scale_map(x: NestedScale, from_: str, to: str, weight: str | None = None,
              by: Sequence[str] = (), **kwargs: object) -> pa.Table:
    """Crosswalk between two frames of a scale.

    One row per pair of overlapping units with `n_from` (atoms in the `from`
    unit), `n_overlap` (atoms shared), `w` (weight of the overlap) and
    `w_from` (full weight of the `from` unit); `w / w_from` is the split share
    of `sum` disaggregation. The label columns are named by the frames; a
    null target marks atoms `to` does not cover. A registered map is returned
    as-is.
    """
    if isinstance(from_, NestedScale) or isinstance(to, NestedScale):
        _stop("`from` and `to` are frame names of `x`; for the map between two "
              "scales use `scale_map_between()`")
    _check_scale(x, "x")
    _check_frame(x, from_, "from")
    _check_frame(x, to, "to")
    if from_ == to:
        v = scale_vocab(x)
        _stop('`from` and `to` are the same %s ("%s"); the map\'s label columns '
              "are named by the %s", v["frame"], from_, v["frames"])
    reg = _get_scale_map(from_, to, _scale_name(x, require=False))
    if reg is not None:
        return reg
    d = scale_atom_pairs(x, from_, to, weight=weight, **kwargs)
    return _finish_map(d, from_, to, by=list(_as_str_tuple(by)))


def scale_map_between(from_: NestedScale, to: NestedScale,
                      weight: str | None = None) -> pa.Table:
    """Crosswalk between two scales through their shared atom keys.

    Label columns are named after the scales. Atoms of `from_` absent from
    `to` get a null target (with a warning).
    """
    _check_scale(from_, "from")
    _check_scale(to, "to")
    from_nm = _scale_name(from_, arg="from")
    to_nm = _scale_name(to, arg="to")
    if from_nm == to_nm:
        _stop('`from` and `to` have the same name ("%s"); the map\'s label columns '
              "are named by the scales -- rename one", from_nm)
    reg = _get_scale_map(from_nm, to_nm)
    if reg is not None:
        return reg

    kf, kt = scale_key(from_), scale_key(to)
    keys_f = _strings(from_.leaftable, kf)
    keys_t = set(_strings(to.leaftable, kt))
    shared = [k for k in keys_f if k in keys_t]
    if not shared:
        keys = "`%s` keys" % kf if kf == kt else "keys"
        hint = scale_vocab(from_).get("register_map", "register_scale_map_between()")
        _stop('the atom layers of "%s" and "%s" share no %s; register an explicit '
              "crosswalk with %s", from_nm, to_nm, keys, hint)
    n_miss = len(keys_f) - len(shared)
    if n_miss > 0:
        _warn('%d atom(s) of "%s" have no counterpart in "%s"; their share is '
              "uncovered (NA target)", n_miss, from_nm, to_nm)
    wcol = _map_weight(from_, weight)
    lf = from_.leaftable
    w = (pa.array([1.0] * lf.num_rows) if wcol is None
         else pc.cast(lf[wcol], pa.float64()))
    d = pa.table({"from": pa.array(keys_f, pa.string()),
                  "to": pa.array([k if k in keys_t else None for k in keys_f],
                                 pa.string()),
                  "w": w})
    return _finish_map(d, from_nm, to_nm)


def _map_weight(x: NestedScale, weight: str | None) -> str | None:
    """The weight column, or None for the unweighted (equal) fallback."""
    if not scale_weights(x) and weight is None:
        return None
    return _resolve_weight(x, weight)


def _finish_map(d: pa.Table, from_lab: str, to_lab: str,
                by: Sequence[str] = ()) -> pa.Table:
    """Aggregate an atom table of from/to/w (+ `by`) into the map schema."""
    by = list(by)
    miss = [c for c in ["from", "to", "w", *by] if c not in d.column_names]
    if miss:
        _stop("the atom correspondence is missing column(s): %s", _preview(miss))
    d = d.filter(pc.is_valid(d["from"]))
    if d.num_rows == 0:
        _stop("no atoms carry a code at `from`; the map would be empty")
    d = d.select([*by, "from", "to", "w"])
    d = d.set_column(d.column_names.index("w"), "w",
                     pc.fill_null(pc.cast(d["w"], pa.float64()), 0.0))
    d = d.append_column("one", pa.array([1] * d.num_rows, pa.int32()))

    grp = [*by, "from", "to"]
    m = d.group_by(grp, use_threads=True).aggregate([("one", "sum"), ("w", "sum")])
    m = m.rename_columns([{"one_sum": "n_overlap", "w_sum": "w"}.get(c, c)
                          for c in m.column_names])
    tot = m.group_by([*by, "from"], use_threads=True).aggregate(
        [("n_overlap", "sum"), ("w", "sum")])
    tot = tot.rename_columns([
        {"n_overlap_sum": "n_from", "w_sum": "w_from"}.get(c, c)
        for c in tot.column_names])
    m = m.join(tot, [*by, "from"], use_threads=True)

    # nulls sort last by default, as R's `na.last = TRUE`
    order = pc.sort_indices(m, sort_keys=[(c, "ascending") for c in grp])
    m = m.take(order).select([*grp, "n_from", "n_overlap", "w", "w_from"])
    m = m.set_column(m.column_names.index("n_from"), "n_from",
                     pc.cast(m["n_from"], pa.int32()))
    m = m.set_column(m.column_names.index("n_overlap"), "n_overlap",
                     pc.cast(m["n_overlap"], pa.int32()))
    return m.rename_columns([{"from": from_lab, "to": to_lab}.get(c, c)
                             for c in m.column_names])


# Registry --------------------------------------------------------------------

def register_scale_map(x: NestedScale | str, from_: str, to: str,
                       map: object) -> str:
    """Register a direct crosswalk between two frames of one scale.

    Scoped to the scale (object or name). `map=None` removes the entry.
    Returns the registry key.
    """
    return _register_map(_map_name_of(x, "x"), _frame_label(from_, "from"),
                         _frame_label(to, "to"), map)


def register_scale_map_between(from_: NestedScale | str, to: NestedScale | str,
                               map: object) -> str:
    """Register a direct crosswalk between two scales (objects or names)."""
    return _register_map("", _map_name_of(from_, "from"), _map_name_of(to, "to"),
                         map)


def _register_map(scope: str, from_nm: str, to_nm: str, map: object) -> str:
    key = "%s%s%s->%s" % (scope, ":" if scope else "", from_nm, to_nm)
    if map is None:
        _MAP_REGISTRY.pop(key, None)
        return key
    if isinstance(map, (str, bytes, int, float)):
        _stop("`map` must be a data.frame (see `scale_map()`) or NULL")
    t = as_table(map, "map")
    miss = [c for c in [from_nm, to_nm, *_MAP_STATS] if c not in t.column_names]
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


def _get_scale_map(from_nm: str, to_nm: str, scope: str = "") -> pa.Table | None:
    keys = ["%s%s%s->%s" % (scope, ":" if scope else "", from_nm, to_nm),
            "%s->%s" % (from_nm, to_nm)]
    for k in dict.fromkeys(keys):
        if k in _MAP_REGISTRY:
            return _MAP_REGISTRY[k]
    return None


def get_scale_map(x: NestedScale | str, from_: str, to: str) -> pa.Table | None:
    """The map registered for two frames of `x`, or None."""
    return _get_scale_map(_frame_label(from_, "from"), _frame_label(to, "to"),
                          scope=_map_name_of(x, "x"))


def get_scale_map_between(from_: NestedScale | str,
                          to: NestedScale | str) -> pa.Table | None:
    """The map registered between two scales, or None."""
    return _get_scale_map(_map_name_of(from_, "from"), _map_name_of(to, "to"))


def list_scale_maps() -> pa.Table:
    """Registry keys, one row each (column `key`)."""
    return pa.table({"key": pa.array(sorted(_MAP_REGISTRY), pa.string())})


def clear_scale_maps() -> None:
    """Remove every registered crosswalk."""
    _MAP_REGISTRY.clear()
